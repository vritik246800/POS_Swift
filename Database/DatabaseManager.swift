import Foundation
import SQLite3

/// Destrutor `SQLITE_TRANSIENT`: manda o SQLite **copiar** o texto durante a
/// chamada a `sqlite3_bind_text`.
///
/// Sem isto (com `nil`, que é `SQLITE_STATIC`) o SQLite guarda só o ponteiro e
/// lê-o mais tarde, no `sqlite3_step`. Como o ponteiro vem de uma `NSString`
/// temporária, pode já ter sido libertado — o valor ligado passa a lixo e a
/// query falha de forma intermitente (ex.: login a recusar credenciais certas).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?

    /// Utilizador autenticado. Definido por `AuthViewModel.login` e limpo no `logout`.
    /// É a base da autorização na camada de dados (S3) — a UI não é a única barreira.
    var currentUser: User?

    private var isAdmin: Bool { currentUser?.role == .admin }

    private init() {
        openDatabase()
        createTables()
        migrateAddBarcode()
        migrateAddPaymentsTable()
        migrateAddDayClosesTable()
    }

    // MARK: - Abrir Base de Dados
    private func openDatabase() {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(Constants.dbName)
            .path

        // SQLITE_OPEN_FULLMUTEX: modo serializado — a mesma ligação pode ser usada
        // a partir de várias threads sem "illegal multi-threaded access".
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK {
            // S13 — integridade referencial activa (por ligação, tem de vir logo a seguir a abrir)
            execute("PRAGMA foreign_keys = ON;")
            protectDatabaseFile(at: path)
            #if DEBUG
            print("✅ Base de dados aberta")
            #endif
        } else {
            #if DEBUG
            print("❌ Erro ao abrir base de dados")
            #endif
        }
    }

    /// S11 — o ficheiro da BD só é legível pelo dono; em iOS fica cifrado em repouso.
    private func protectDatabaseFile(at path: String) {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: Int16(0o600))]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: path)
    }

    // MARK: - Criar Tabelas
    private func createTables() {
        createUsersTable()
        createProductsTable()
        createSalesTable()
        createSaleItemsTable()
        createReportsTable()
        createPaymentsTable()
        createDayClosesTable()
        createAuditLogTable()
        // 1.1 — Categorias
        createCategoriesTable()
        migrateAddCategoryToProducts()
        migrateAddDiscountToProducts()
        seedDefaultCategories()
        // 1.2 — Lotes
        createBatchesTable()
        migrateStockToBatches()
        // Administração — fecho por caixa
        createCashierClosesTable()
    }

    private func execute(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        } else {
            #if DEBUG
            print("❌ Erro SQL: \(sql)")
            #endif
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Transações (S4)

    /// Corre `body` dentro de `BEGIN IMMEDIATE`. `nil` devolvido pelo corpo → `ROLLBACK`.
    /// Não é reentrante: nunca chamar dentro de outra transação.
    @discardableResult
    func transaction<T>(_ body: () -> T?) -> T? {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else { return nil }
        guard let result = body() else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return nil
        }
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK { return result }
        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        return nil
    }

    private func createUsersTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'cashier'
            );
        """)
    }

    private func createProductsTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                barcode TEXT UNIQUE NOT NULL DEFAULT '',
                price_base REAL NOT NULL,
                iva_rate REAL NOT NULL DEFAULT 16.0,
                profit_margin REAL NOT NULL DEFAULT 0.0,
                price_final REAL NOT NULL,
                stock INTEGER NOT NULL DEFAULT 0,
                discount_percent REAL NOT NULL DEFAULT 0.0
            );
        """)
    }

    /// Desconto de promoção por produto (1.2). Coluna acrescentada a bases antigas.
    private func migrateAddDiscountToProducts() {
        guard !columnExists("discount_percent", inTable: "Products") else { return }
        execute("ALTER TABLE Products ADD COLUMN discount_percent REAL NOT NULL DEFAULT 0.0;")
    }

    private func migrateAddBarcode() {
        let checkSQL = "PRAGMA table_info(Products);"
        var statement: OpaquePointer?
        var hasBarcode = false

        if sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let colName = sqlite3_column_text(statement, 1),
                   String(cString: colName) == "barcode" {
                    hasBarcode = true
                }
            }
        }
        sqlite3_finalize(statement)

        if !hasBarcode {
            execute("ALTER TABLE Products ADD COLUMN barcode TEXT NOT NULL DEFAULT '';")
            execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON Products(barcode) WHERE barcode != '';")
            #if DEBUG
            print("✅ Migração: coluna barcode adicionada")
            #endif
        } else {
            execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON Products(barcode) WHERE barcode != '';")
        }
    }

    private func createSalesTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Sales (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                client_name TEXT,
                client_nif TEXT,
                total REAL NOT NULL,
                date TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'completed',
                FOREIGN KEY(user_id) REFERENCES Users(id)
            );
        """)
    }

    private func createSaleItemsTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS SaleItems (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sale_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                product_name TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                unit_price REAL NOT NULL,
                subtotal REAL NOT NULL,
                FOREIGN KEY(sale_id) REFERENCES Sales(id),
                FOREIGN KEY(product_id) REFERENCES Products(id)
            );
        """)
    }

    private func createReportsTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                period TEXT NOT NULL,
                file_path TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)
    }

    // MARK: - Payments Table
    func createPaymentsTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Payments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sale_id INTEGER NOT NULL,
                method TEXT NOT NULL,
                amount REAL NOT NULL,
                reference TEXT NOT NULL DEFAULT '',
                FOREIGN KEY(sale_id) REFERENCES Sales(id)
            );
        """)
    }

    func migrateAddPaymentsTable() {
        createPaymentsTable()
    }

    // MARK: - DayCloses Table
    func createDayClosesTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS DayCloses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL UNIQUE,
                total_sales REAL NOT NULL DEFAULT 0,
                total_cash REAL NOT NULL DEFAULT 0,
                total_card REAL NOT NULL DEFAULT 0,
                total_bank_transfer REAL NOT NULL DEFAULT 0,
                total_mpesa REAL NOT NULL DEFAULT 0,
                total_emola REAL NOT NULL DEFAULT 0,
                num_sales INTEGER NOT NULL DEFAULT 0,
                notes TEXT NOT NULL DEFAULT '',
                closed_by INTEGER NOT NULL,
                closed_at TEXT NOT NULL,
                FOREIGN KEY(closed_by) REFERENCES Users(id)
            );
        """)
    }

    func migrateAddDayClosesTable() {
        createDayClosesTable()
    }

    // MARK: - Fechar Base de Dados
    func closeDatabase() {
        if sqlite3_close(db) == SQLITE_OK {
            #if DEBUG
            print("✅ Base de dados fechada")
            #endif
        }
    }

    // MARK: - AuditLog

    private func createAuditLogTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS AuditLog (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                action TEXT NOT NULL,
                entity TEXT NOT NULL,
                entity_id INTEGER,
                timestamp TEXT NOT NULL
            );
        """)
    }

    /// Regista um evento sensível. Nunca guardar aqui passwords, hashes ou caminhos.
    func logAudit(action: String, entity: String, entityId: Int?, userId: Int? = nil) {
        let sql = "INSERT INTO AuditLog (user_id, action, entity, entity_id, timestamp) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        let uid = userId ?? currentUser?.id
        if let uid { sqlite3_bind_int(statement, 1, Int32(uid)) } else { sqlite3_bind_null(statement, 1) }
        sqlite3_bind_text(statement, 2, (action as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (entity as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if let entityId { sqlite3_bind_int(statement, 4, Int32(entityId)) } else { sqlite3_bind_null(statement, 4) }
        sqlite3_bind_text(statement, 5, (ISO8601DateFormatter().string(from: Date()) as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    // MARK: - Users

    func createUser(name: String, username: String, passwordHash: String, role: UserRole) -> Bool {
        let sql = "INSERT INTO Users (name, username, password_hash, role) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (username as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (passwordHash as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, (role.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    func fetchUsers() -> [User] {
        let sql = "SELECT id, name, username, password_hash, role FROM Users;"
        var statement: OpaquePointer?
        var users: [User] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let username = String(cString: sqlite3_column_text(statement, 2))
            let passwordHash = String(cString: sqlite3_column_text(statement, 3))
            let roleRaw = String(cString: sqlite3_column_text(statement, 4))
            let role = UserRole(rawValue: roleRaw) ?? .cashier
            users.append(User(id: id, name: name, username: username, passwordHash: passwordHash, role: role))
        }
        sqlite3_finalize(statement)
        return users
    }

    func fetchUserByUsername(_ username: String) -> User? {
        let sql = "SELECT id, name, username, password_hash, role FROM Users WHERE username = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, (username as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let user_username = String(cString: sqlite3_column_text(statement, 2))
            let passwordHash = String(cString: sqlite3_column_text(statement, 3))
            let roleRaw = String(cString: sqlite3_column_text(statement, 4))
            let role = UserRole(rawValue: roleRaw) ?? .cashier
            sqlite3_finalize(statement)
            return User(id: id, name: name, username: user_username, passwordHash: passwordHash, role: role)
        }
        sqlite3_finalize(statement)
        return nil
    }

    /// Número de administradores existentes — suporta a regra do "último Admin".
    func adminCount() -> Int {
        let sql = "SELECT COUNT(*) FROM Users WHERE role = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_text(statement, 1, (UserRole.admin.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW { count = Int(sqlite3_column_int(statement, 0)) }
        sqlite3_finalize(statement)
        return count
    }

    private func user(id: Int) -> User? {
        fetchUsers().first { $0.id == id }
    }

    func deleteUser(id: Int) -> Bool {
        // S3 — só Admin apaga utilizadores, e o último Admin nunca é apagado.
        guard isAdmin else { return false }
        if let existing = user(id: id), existing.role == .admin, adminCount() <= 1 { return false }
        let sql = "DELETE FROM Users WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_int(statement, 1, Int32(id))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if result { logAudit(action: "user_deleted", entity: "Users", entityId: id) }
        return result
    }

    func updateUser(_ user: User) -> Bool {
        // S3 — Admin edita qualquer um; um utilizador só pode editar-se a si próprio
        // (necessário para a migração de hash no login) e nunca muda o próprio perfil.
        let isSelf = currentUser?.id == user.id
        guard isAdmin || isSelf else { return false }
        let existing = self.user(id: user.id)
        if !isAdmin, let existing, existing.role != user.role { return false }
        // O último Admin não pode ser despromovido.
        if let existing, existing.role == .admin, user.role != .admin, adminCount() <= 1 { return false }

        let sql = "UPDATE Users SET name=?, username=?, password_hash=?, role=? WHERE id=?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (user.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (user.username as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (user.passwordHash as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, (user.role.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 5, Int32(user.id))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if result { logAudit(action: "user_updated", entity: "Users", entityId: user.id) }
        return result
    }

    // MARK: - Products

    func createProduct(name: String, barcode: String, priceBase: Double, ivaRate: Double, profitMargin: Double, stock: Int,
                       categoryId: Int? = nil, expiryDate: Date? = nil) -> Bool {
        let priceFinal = Product.calculateFinalPrice(base: priceBase, profit: profitMargin, iva: ivaRate)
        let sql = "INSERT INTO Products (name, barcode, price_base, iva_rate, profit_margin, price_final, stock, category_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
        return transaction { () -> Bool? in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, (barcode as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, priceBase)
            sqlite3_bind_double(statement, 4, ivaRate)
            sqlite3_bind_double(statement, 5, profitMargin)
            sqlite3_bind_double(statement, 6, priceFinal)
            sqlite3_bind_int(statement, 7, Int32(stock))
            if let categoryId { sqlite3_bind_int(statement, 8, Int32(categoryId)) } else { sqlite3_bind_null(statement, 8) }
            let ok = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            guard ok else { return nil }

            // O stock inicial tem de nascer como lote, senão o próximo sync apaga-o.
            let productId = Int(sqlite3_last_insert_rowid(db))
            if stock > 0 {
                guard insertBatch(productId: productId, quantity: stock, priceBase: priceBase,
                                  expiryDate: expiryDate, receivedAt: Date()) else { return nil }
                syncProductStock(productId: productId)
            }
            return true
        } ?? false
    }

    func fetchProducts() -> [Product] {
        let sql = "SELECT id, name, barcode, price_base, iva_rate, profit_margin, price_final, stock, category_id, discount_percent FROM Products ORDER BY name;"
        var statement: OpaquePointer?
        var products: [Product] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(statement) == SQLITE_ROW {
            products.append(productFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return products
    }

    func searchProducts(query: String) -> [Product] {
        let sql = """
            SELECT id, name, barcode, price_base, iva_rate, profit_margin, price_final, stock, category_id, discount_percent
            FROM Products WHERE name LIKE ? OR barcode LIKE ? ORDER BY name;
        """
        var statement: OpaquePointer?
        var products: [Product] = []
        let pattern = "%\(query)%" as NSString
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, pattern.utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, pattern.utf8String, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
            products.append(productFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return products
    }

    func fetchProductByBarcode(_ barcode: String) -> Product? {
        let sql = "SELECT id, name, barcode, price_base, iva_rate, profit_margin, price_final, stock, category_id, discount_percent FROM Products WHERE barcode = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, (barcode as NSString).utf8String, -1, SQLITE_TRANSIENT)
        var product: Product? = nil
        if sqlite3_step(statement) == SQLITE_ROW {
            product = productFromStatement(statement)
        }
        sqlite3_finalize(statement)
        return product
    }

    func fetchProduct(id: Int) -> Product? {
        let sql = "SELECT id, name, barcode, price_base, iva_rate, profit_margin, price_final, stock, category_id, discount_percent FROM Products WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int(statement, 1, Int32(id))
        var product: Product? = nil
        if sqlite3_step(statement) == SQLITE_ROW { product = productFromStatement(statement) }
        sqlite3_finalize(statement)
        return product
    }

    func updateProduct(_ product: Product) -> Bool {
        // S3 — alterar preço é operação de Admin.
        let existing = fetchProduct(id: product.id)
        let priceChanged = existing.map {
            $0.priceBase != product.priceBase || $0.profitMargin != product.profitMargin || $0.ivaRate != product.ivaRate
        } ?? false
        if priceChanged && !isAdmin { return false }

        let priceFinal = Product.calculateFinalPrice(base: product.priceBase, profit: product.profitMargin, iva: product.ivaRate)
        let sql = "UPDATE Products SET name=?, barcode=?, price_base=?, iva_rate=?, profit_margin=?, price_final=?, category_id=? WHERE id=?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (product.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (product.barcode as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, product.priceBase)
        sqlite3_bind_double(statement, 4, product.ivaRate)
        sqlite3_bind_double(statement, 5, product.profitMargin)
        sqlite3_bind_double(statement, 6, priceFinal)
        if let categoryId = product.categoryId { sqlite3_bind_int(statement, 7, Int32(categoryId)) } else { sqlite3_bind_null(statement, 7) }
        sqlite3_bind_int(statement, 8, Int32(product.id))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)

        // `stock` é derivado dos lotes (`syncProductStock`) e nunca é escrito aqui:
        // o produto que chega do formulário é um retrato tirado ao abrir a sheet e
        // repor esse valor apagava os lotes entretanto criados ou editados.
        if result, priceChanged {
            logAudit(action: "price_changed", entity: "Products", entityId: product.id)
        }
        return result
    }

    /// Assinatura mantida (usada por `LowStockView`), mas o stock passa a viver nos lotes.
    func updateStock(productId: Int, newStock: Int) -> Bool {
        guard newStock >= 0 else { return false }
        return transaction { adjustStockToBatches(productId: productId, newStock: newStock) ? true : nil } ?? false
    }

    func deleteProduct(id: Int) -> Bool {
        guard isAdmin else { return false }   // S3
        let sql = "DELETE FROM Products WHERE id=?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_int(statement, 1, Int32(id))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if result { logAudit(action: "product_deleted", entity: "Products", entityId: id) }
        return result
    }

    private func productFromStatement(_ statement: OpaquePointer?) -> Product {
        let id = Int(sqlite3_column_int(statement, 0))
        let name = String(cString: sqlite3_column_text(statement, 1))
        let barcode = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
        let priceBase = sqlite3_column_double(statement, 3)
        let ivaRate = sqlite3_column_double(statement, 4)
        let profitMargin = sqlite3_column_double(statement, 5)
        let priceFinal = sqlite3_column_double(statement, 6)
        let stock = Int(sqlite3_column_int(statement, 7))
        let categoryId = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8))
        let discount = sqlite3_column_double(statement, 9)
        return Product(id: id, name: name, barcode: barcode, priceBase: priceBase, ivaRate: ivaRate, profitMargin: profitMargin, priceFinal: priceFinal, stock: stock, categoryId: categoryId, discountPercent: discount)
    }

    /// Promoção de um produto: desconto em percentagem sobre o preço final.
    /// S3 — mexer no preço é operação de Admin.
    func setProductDiscount(productId: Int, percent: Double) -> Bool {
        guard isAdmin else { return false }
        guard percent >= 0, percent <= 90 else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE Products SET discount_percent = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_double(statement, 1, percent)
        sqlite3_bind_int(statement, 2, Int32(productId))
        let ok = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if ok { logAudit(action: "discount_changed", entity: "Products", entityId: productId) }
        return ok
    }

    // MARK: - Sales

    /// Venda atómica (S4 + S15 + FIFO): Sales + SaleItems + consumo de lotes + Payments
    /// numa única transação. Stock é revalidado **dentro** da transação.
    func createSaleAtomic(userId: Int, clientName: String, clientNIF: String,
                          items: [SaleItem], total: Double, payments: [Payment] = []) -> Int? {
        guard !items.isEmpty else { return nil }
        let dateStr = ISO8601DateFormatter().string(from: Date())

        return transaction { () -> Int? in
            // S15 — revalidar stock aqui dentro, não antes de abrir a transação.
            for item in items {
                guard item.quantity > 0, sellableStock(productId: item.productId) >= item.quantity else { return nil }
            }

            let sql = "INSERT INTO Sales (user_id, client_name, client_nif, total, date, status) VALUES (?, ?, ?, ?, ?, 'completed');"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int(statement, 1, Int32(userId))
            sqlite3_bind_text(statement, 2, (clientName as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, (clientNIF as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 4, total)
            sqlite3_bind_text(statement, 5, (dateStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            let inserted = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            guard inserted else { return nil }

            let saleId = Int(sqlite3_last_insert_rowid(db))
            for item in items {
                guard createSaleItem(saleId: saleId, item: item) else { return nil }
                guard consumeStockFIFOUnsafe(productId: item.productId, quantity: item.quantity, excludeExpired: true) else { return nil }
            }
            guard insertPayments(payments, saleId: saleId) else { return nil }
            return saleId
        }
    }

    /// Mantido para não partir chamadores existentes — delega no caminho atómico.
    func createSale(userId: Int, clientName: String, clientNIF: String, items: [SaleItem], total: Double) -> Int? {
        createSaleAtomic(userId: userId, clientName: clientName, clientNIF: clientNIF, items: items, total: total)
    }

    /// S3 — apagar uma venda é operação de Admin (e fica registada).
    func deleteSale(id: Int) -> Bool {
        guard isAdmin else { return false }
        return transaction { () -> Bool? in
            for sql in ["DELETE FROM Payments WHERE sale_id = ?;",
                        "DELETE FROM SaleItems WHERE sale_id = ?;",
                        "DELETE FROM Sales WHERE id = ?;"] {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
                sqlite3_bind_int(statement, 1, Int32(id))
                let ok = sqlite3_step(statement) == SQLITE_DONE
                sqlite3_finalize(statement)
                guard ok else { return nil }
            }
            logAudit(action: "sale_deleted", entity: "Sales", entityId: id)
            return true
        } ?? false
    }

    private func createSaleItem(saleId: Int, item: SaleItem) -> Bool {
        let sql = "INSERT INTO SaleItems (sale_id, product_id, product_name, quantity, unit_price, subtotal) VALUES (?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_int(statement, 1, Int32(saleId))
        sqlite3_bind_int(statement, 2, Int32(item.productId))
        sqlite3_bind_text(statement, 3, (item.productName as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(item.quantity))
        sqlite3_bind_double(statement, 5, item.unitPrice)
        sqlite3_bind_double(statement, 6, item.subtotal)
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    func fetchSales() -> [Sale] {
        let sql = "SELECT id, user_id, client_name, client_nif, total, date, status FROM Sales ORDER BY date DESC;"
        var statement: OpaquePointer?
        var sales: [Sale] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(statement) == SQLITE_ROW {
            sales.append(saleFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return sales
    }

    func fetchSaleItems(saleId: Int) -> [SaleItem] {
        let sql = "SELECT id, sale_id, product_id, product_name, quantity, unit_price, subtotal FROM SaleItems WHERE sale_id = ?;"
        var statement: OpaquePointer?
        var items: [SaleItem] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(statement, 1, Int32(saleId))
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let saleId = Int(sqlite3_column_int(statement, 1))
            let productId = Int(sqlite3_column_int(statement, 2))
            let productName = String(cString: sqlite3_column_text(statement, 3))
            let quantity = Int(sqlite3_column_int(statement, 4))
            let unitPrice = sqlite3_column_double(statement, 5)
            let subtotal = sqlite3_column_double(statement, 6)
            items.append(SaleItem(id: id, saleId: saleId, productId: productId, productName: productName, quantity: quantity, unitPrice: unitPrice, subtotal: subtotal))
        }
        sqlite3_finalize(statement)
        return items
    }

    func fetchSalesByDate(date: String) -> [Sale] {
        let sql = "SELECT id, user_id, client_name, client_nif, total, date, status FROM Sales WHERE date LIKE ? ORDER BY date DESC;"
        var statement: OpaquePointer?
        var sales: [Sale] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, ("%\(date)%" as NSString).utf8String, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
            sales.append(saleFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return sales
    }

    func fetchSalesByMonth(yearMonth: String) -> [Sale] {
        return fetchSalesByDate(date: yearMonth)
    }

    /// Vendas de um ano (`"2026"`). Prefixo, não `%…%`: um `LIKE '%2026%'`
    /// apanharia também a hora de outras datas (ex.: `…T20:26:…`).
    func fetchSalesByYear(year: String) -> [Sale] {
        let sql = "SELECT id, user_id, client_name, client_nif, total, date, status FROM Sales WHERE date LIKE ? ORDER BY date DESC;"
        var statement: OpaquePointer?
        var sales: [Sale] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, ("\(year)-%" as NSString).utf8String, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
            sales.append(saleFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return sales
    }

    private func saleFromStatement(_ statement: OpaquePointer?) -> Sale {
        let id = Int(sqlite3_column_int(statement, 0))
        let userId = Int(sqlite3_column_int(statement, 1))
        let clientName = String(cString: sqlite3_column_text(statement, 2))
        let clientNIF = String(cString: sqlite3_column_text(statement, 3))
        let total = sqlite3_column_double(statement, 4)
        let dateStr = String(cString: sqlite3_column_text(statement, 5))
        let statusRaw = String(cString: sqlite3_column_text(statement, 6))
        let status = SaleStatus(rawValue: statusRaw) ?? .completed
        let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        let items = fetchSaleItems(saleId: id)
        return Sale(id: id, userId: userId, clientName: clientName, clientNIF: clientNIF, items: items, total: total, date: date, status: status)
    }

    // MARK: - Payments

    func createPayments(_ payments: [Payment], saleId: Int) {
        _ = insertPayments(payments, saleId: saleId)
    }

    /// Sem transação própria — usado dentro da transação da venda.
    @discardableResult
    private func insertPayments(_ payments: [Payment], saleId: Int) -> Bool {
        for p in payments {
            let sql = "INSERT INTO Payments (sale_id, method, amount, reference) VALUES (?, ?, ?, ?);"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
            sqlite3_bind_int(statement, 1, Int32(saleId))
            sqlite3_bind_text(statement, 2, (p.method.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, p.amount)
            sqlite3_bind_text(statement, 4, (p.reference as NSString).utf8String, -1, SQLITE_TRANSIENT)
            let ok = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            guard ok else { return false }
        }
        return true
    }

    func fetchPayments(saleId: Int) -> [Payment] {
        let sql = "SELECT id, sale_id, method, amount, reference FROM Payments WHERE sale_id = ?;"
        var statement: OpaquePointer?
        var payments: [Payment] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(statement, 1, Int32(saleId))
        while sqlite3_step(statement) == SQLITE_ROW {
            payments.append(paymentFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return payments
    }

    func fetchPaymentsByDate(datePrefix: String) -> [Payment] {
        let sql = """
            SELECT p.id, p.sale_id, p.method, p.amount, p.reference
            FROM Payments p INNER JOIN Sales s ON p.sale_id = s.id
            WHERE s.date LIKE ?;
        """
        var statement: OpaquePointer?
        var payments: [Payment] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, ("%\(datePrefix)%" as NSString).utf8String, -1, SQLITE_TRANSIENT)
        while sqlite3_step(statement) == SQLITE_ROW {
            payments.append(paymentFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return payments
    }

    private func paymentFromStatement(_ s: OpaquePointer?) -> Payment {
        let id = Int(sqlite3_column_int(s, 0))
        let sid = Int(sqlite3_column_int(s, 1))
        let methodRaw = String(cString: sqlite3_column_text(s, 2))
        let amount = sqlite3_column_double(s, 3)
        let ref = String(cString: sqlite3_column_text(s, 4))
        let method = PaymentMethod(rawValue: methodRaw) ?? .cash
        return Payment(id: id, saleId: sid, method: method, amount: amount, reference: ref)
    }

    // MARK: - DayClose

    func saveDayClose(date: String, totalSales: Double, cash: Double, card: Double,
                      bankTransfer: Double, mpesa: Double, emola: Double,
                      numSales: Int, notes: String, closedBy: Int) -> Bool {
        let closedAt = ISO8601DateFormatter().string(from: Date())
        let sql = """
            INSERT OR REPLACE INTO DayCloses
            (date, total_sales, total_cash, total_card, total_bank_transfer, total_mpesa, total_emola, num_sales, notes, closed_by, closed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, totalSales)
        sqlite3_bind_double(statement, 3, cash)
        sqlite3_bind_double(statement, 4, card)
        sqlite3_bind_double(statement, 5, bankTransfer)
        sqlite3_bind_double(statement, 6, mpesa)
        sqlite3_bind_double(statement, 7, emola)
        sqlite3_bind_int(statement, 8, Int32(numSales))
        sqlite3_bind_text(statement, 9, (notes as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 10, Int32(closedBy))
        sqlite3_bind_text(statement, 11, (closedAt as NSString).utf8String, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if result { logAudit(action: "day_closed", entity: "DayCloses", entityId: nil, userId: closedBy) }
        return result
    }

    /// S3 — reabrir um fecho de caixa é operação de Admin.
    func reopenDayClose(date: String) -> Bool {
        guard isAdmin else { return false }
        let sql = "DELETE FROM DayCloses WHERE date = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if result { logAudit(action: "day_reopened", entity: "DayCloses", entityId: nil) }
        return result
    }

    func fetchDayClose(date: String) -> DayClose? {
        let sql = "SELECT id, date, total_sales, total_cash, total_card, total_bank_transfer, total_mpesa, total_emola, num_sales, notes, closed_by, closed_at FROM DayCloses WHERE date = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        var dc: DayClose? = nil
        if sqlite3_step(statement) == SQLITE_ROW {
            dc = dayCloseFromStatement(statement)
        }
        sqlite3_finalize(statement)
        return dc
    }

    func fetchDayCloses(monthPrefix: String? = nil) -> [DayClose] {
        // S1 — o prefixo do mês é ligado como parâmetro, nunca interpolado no SQL.
        let columns = "id, date, total_sales, total_cash, total_card, total_bank_transfer, total_mpesa, total_emola, num_sales, notes, closed_by, closed_at"
        let sql = monthPrefix == nil
            ? "SELECT \(columns) FROM DayCloses ORDER BY date DESC;"
            : "SELECT \(columns) FROM DayCloses WHERE date LIKE ? ORDER BY date DESC;"
        var statement: OpaquePointer?
        var closes: [DayClose] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        if let month = monthPrefix {
            sqlite3_bind_text(statement, 1, ("\(month)%" as NSString).utf8String, -1, SQLITE_TRANSIENT)
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            closes.append(dayCloseFromStatement(statement))
        }
        sqlite3_finalize(statement)
        return closes
    }

    private func dayCloseFromStatement(_ s: OpaquePointer?) -> DayClose {
        DayClose(
            id: Int(sqlite3_column_int(s, 0)),
            date: String(cString: sqlite3_column_text(s, 1)),
            totalSales: sqlite3_column_double(s, 2),
            totalCash: sqlite3_column_double(s, 3),
            totalCard: sqlite3_column_double(s, 4),
            totalBankTransfer: sqlite3_column_double(s, 5),
            totalMpesa: sqlite3_column_double(s, 6),
            totalEmola: sqlite3_column_double(s, 7),
            numSales: Int(sqlite3_column_int(s, 8)),
            notes: String(cString: sqlite3_column_text(s, 9)),
            closedBy: Int(sqlite3_column_int(s, 10)),
            closedAt: ISO8601DateFormatter().date(from: String(cString: sqlite3_column_text(s, 11))) ?? Date()
        )
    }

    func isDayAlreadyClosed(date: String) -> Bool {
        fetchDayClose(date: date) != nil
    }

    // MARK: - CashierCloses (fecho por caixa)

    private func createCashierClosesTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS CashierCloses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                user_id INTEGER NOT NULL,
                total_sales REAL NOT NULL DEFAULT 0,
                total_cash REAL NOT NULL DEFAULT 0,
                total_card REAL NOT NULL DEFAULT 0,
                total_bank_transfer REAL NOT NULL DEFAULT 0,
                total_mpesa REAL NOT NULL DEFAULT 0,
                total_emola REAL NOT NULL DEFAULT 0,
                num_sales INTEGER NOT NULL DEFAULT 0,
                notes TEXT NOT NULL DEFAULT '',
                closed_by INTEGER NOT NULL,
                closed_at TEXT NOT NULL,
                UNIQUE(date, user_id),
                FOREIGN KEY(user_id) REFERENCES Users(id),
                FOREIGN KEY(closed_by) REFERENCES Users(id)
            );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_cashier_closes_date ON CashierCloses(date);")
    }

    private static let cashierCloseColumns =
        "id, date, user_id, total_sales, total_cash, total_card, total_bank_transfer, total_mpesa, total_emola, num_sales, notes, closed_by, closed_at"

    /// Grava (ou substitui) o fecho da caixa de um utilizador num dia.
    /// S3 — o Caixa só pode fechar a sua própria caixa; o Admin pode fechar qualquer uma.
    func saveCashierClose(date: String, userId: Int, totalSales: Double,
                          cash: Double, card: Double, bankTransfer: Double,
                          mpesa: Double, emola: Double, numSales: Int, notes: String) -> Bool {
        guard let closedBy = currentUser?.id else { return false }
        guard isAdmin || closedBy == userId else { return false }

        let sql = """
            INSERT OR REPLACE INTO CashierCloses
            (date, user_id, total_sales, total_cash, total_card, total_bank_transfer, total_mpesa, total_emola, num_sales, notes, closed_by, closed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(userId))
        sqlite3_bind_double(statement, 3, totalSales)
        sqlite3_bind_double(statement, 4, cash)
        sqlite3_bind_double(statement, 5, card)
        sqlite3_bind_double(statement, 6, bankTransfer)
        sqlite3_bind_double(statement, 7, mpesa)
        sqlite3_bind_double(statement, 8, emola)
        sqlite3_bind_int(statement, 9, Int32(numSales))
        sqlite3_bind_text(statement, 10, (notes as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 11, Int32(closedBy))
        sqlite3_bind_text(statement, 12, (ISO8601DateFormatter().string(from: Date()) as NSString).utf8String, -1, SQLITE_TRANSIENT)
        let ok = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if ok { logAudit(action: "cashier_closed", entity: "CashierCloses", entityId: userId) }
        return ok
    }

    /// Fechos de caixa de um dia. Sem data devolve todos, do mais recente para o mais antigo.
    func fetchCashierCloses(date: String? = nil) -> [CashierClose] {
        let sql = date == nil
            ? "SELECT \(Self.cashierCloseColumns) FROM CashierCloses ORDER BY date DESC, user_id;"
            : "SELECT \(Self.cashierCloseColumns) FROM CashierCloses WHERE date = ? ORDER BY user_id;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        if let date { sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT) }
        var closes: [CashierClose] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            closes.append(CashierClose(
                id: Int(sqlite3_column_int(statement, 0)),
                date: String(cString: sqlite3_column_text(statement, 1)),
                userId: Int(sqlite3_column_int(statement, 2)),
                totalSales: sqlite3_column_double(statement, 3),
                totalCash: sqlite3_column_double(statement, 4),
                totalCard: sqlite3_column_double(statement, 5),
                totalBankTransfer: sqlite3_column_double(statement, 6),
                totalMpesa: sqlite3_column_double(statement, 7),
                totalEmola: sqlite3_column_double(statement, 8),
                numSales: Int(sqlite3_column_int(statement, 9)),
                notes: String(cString: sqlite3_column_text(statement, 10)),
                closedBy: Int(sqlite3_column_int(statement, 11)),
                closedAt: ISO8601DateFormatter().date(from: String(cString: sqlite3_column_text(statement, 12))) ?? Date()
            ))
        }
        sqlite3_finalize(statement)
        return closes
    }

    /// S3 — reabrir o fecho de uma caixa é operação de Admin.
    func reopenCashierClose(date: String, userId: Int) -> Bool {
        guard isAdmin else { return false }
        let sql = "DELETE FROM CashierCloses WHERE date = ? AND user_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(userId))
        let ok = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        if ok { logAudit(action: "cashier_reopened", entity: "CashierCloses", entityId: userId) }
        return ok
    }

    // MARK: - Última venda por produto (produtos parados)

    /// Data da última venda concluída de cada produto. Produtos que nunca foram
    /// vendidos não aparecem no dicionário.
    func lastSaleDates() -> [Int: Date] {
        let sql = """
            SELECT si.product_id, MAX(s.date)
            FROM SaleItems si
            JOIN Sales s ON s.id = si.sale_id
            WHERE s.status = 'completed'
            GROUP BY si.product_id;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        var result: [Int: Date] = [:]
        let formatter = ISO8601DateFormatter()
        while sqlite3_step(statement) == SQLITE_ROW {
            let productId = Int(sqlite3_column_int(statement, 0))
            guard let raw = sqlite3_column_text(statement, 1) else { continue }
            if let date = formatter.date(from: String(cString: raw)) {
                result[productId] = date
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    // MARK: - Reports

    func saveReport(type: ReportType, period: String, filePath: String, createdAt: String) -> Bool {
        let sql = "INSERT INTO Reports (type, period, file_path, created_at) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (type.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (period as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (filePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, (createdAt as NSString).utf8String, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    /// Remove o registo do relatório. O ficheiro em disco é da
    /// responsabilidade de quem chama (ver `ReportHistoryView`).
    func deleteReport(id: Int) -> Bool {
        let sql = "DELETE FROM Reports WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_int(statement, 1, Int32(id))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    func fetchReports() -> [Report] {
        let sql = "SELECT id, type, period, file_path, created_at FROM Reports ORDER BY created_at DESC;"
        var statement: OpaquePointer?
        var reports: [Report] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let typeRaw = String(cString: sqlite3_column_text(statement, 1))
            let period = String(cString: sqlite3_column_text(statement, 2))
            let filePath = String(cString: sqlite3_column_text(statement, 3))
            let createdAtStr = String(cString: sqlite3_column_text(statement, 4))
            let type = ReportType(rawValue: typeRaw) ?? .daily
            let createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()
            reports.append(Report(id: id, type: type, period: period, filePath: filePath, createdAt: createdAt))
        }
        sqlite3_finalize(statement)
        return reports
    }

    // MARK: - Categories (1.1)

    private func createCategoriesTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                icon TEXT NOT NULL DEFAULT 'cube.box.fill',
                color_hex TEXT NOT NULL DEFAULT '5856D6',
                sort_order INTEGER NOT NULL DEFAULT 0
            );
        """)
    }

    private func migrateAddCategoryToProducts() {
        guard !columnExists("category_id", inTable: "Products") else {
            execute("CREATE INDEX IF NOT EXISTS idx_products_category ON Products(category_id);")
            return
        }
        execute("ALTER TABLE Products ADD COLUMN category_id INTEGER REFERENCES Categories(id);")
        execute("CREATE INDEX IF NOT EXISTS idx_products_category ON Products(category_id);")
    }

    private func columnExists(_ column: String, inTable table: String) -> Bool {
        // `table` nunca vem do utilizador — só de literais internos.
        var statement: OpaquePointer?
        var found = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1), String(cString: name) == column { found = true }
            }
        }
        sqlite3_finalize(statement)
        return found
    }

    private func seedDefaultCategories() {
        guard fetchCategories().isEmpty else { return }
        let defaults: [(String, String, String)] = [
            ("Bebidas",   "cup.and.saucer.fill",        "007AFF"),
            ("Alimentos", "carrot.fill",                "FF9500"),
            ("Limpeza",   "bubbles.and.sparkles.fill",  "34C759"),
            ("Higiene",   "drop.fill",                  "5AC8FA"),
            ("Papelaria", "pencil.and.ruler.fill",      "AF52DE"),
            ("Outros",    "shippingbox.fill",           "8E8E93")
        ]
        for (index, item) in defaults.enumerated() {
            _ = createCategory(name: item.0, icon: item.1, colorHex: item.2, sortOrder: index)
        }
    }

    func fetchCategories() -> [Category] {
        let sql = "SELECT id, name, icon, color_hex, sort_order FROM Categories ORDER BY sort_order, name;"
        var statement: OpaquePointer?
        var categories: [Category] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(statement) == SQLITE_ROW {
            categories.append(Category(
                id: Int(sqlite3_column_int(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                icon: String(cString: sqlite3_column_text(statement, 2)),
                colorHex: String(cString: sqlite3_column_text(statement, 3)),
                sortOrder: Int(sqlite3_column_int(statement, 4))
            ))
        }
        sqlite3_finalize(statement)
        return categories
    }

    func createCategory(name: String, icon: String, colorHex: String, sortOrder: Int) -> Bool {
        let sql = "INSERT INTO Categories (name, icon, color_hex, sort_order) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (icon as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (colorHex as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(sortOrder))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    func updateCategory(_ category: Category) -> Bool {
        let sql = "UPDATE Categories SET name=?, icon=?, color_hex=?, sort_order=? WHERE id=?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (category.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (category.icon as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (category.colorHex as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(category.sortOrder))
        sqlite3_bind_int(statement, 5, Int32(category.id))
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    /// Apagar a categoria nunca apaga produtos — só os deixa "Sem categoria".
    func deleteCategory(id: Int) -> Bool {
        transaction { () -> Bool? in
            for sql in ["UPDATE Products SET category_id = NULL WHERE category_id = ?;",
                        "DELETE FROM Categories WHERE id = ?;"] {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
                sqlite3_bind_int(statement, 1, Int32(id))
                let ok = sqlite3_step(statement) == SQLITE_DONE
                sqlite3_finalize(statement)
                guard ok else { return nil }
            }
            return true
        } ?? false
    }

    /// Grava a nova ordem das categorias: `sort_order` = posição no array.
    /// Tudo numa transação — ou fica a ordem toda, ou não fica nada.
    func reorderCategories(_ orderedIDs: [Int]) -> Bool {
        transaction { () -> Bool? in
            let sql = "UPDATE Categories SET sort_order = ? WHERE id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            for (index, id) in orderedIDs.enumerated() {
                sqlite3_reset(statement)
                sqlite3_bind_int(statement, 1, Int32(index))
                sqlite3_bind_int(statement, 2, Int32(id))
                guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
            }
            return true
        } ?? false
    }

    func productCount(inCategory id: Int) -> Int {
        let sql = "SELECT COUNT(*) FROM Products WHERE category_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_int(statement, 1, Int32(id))
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW { count = Int(sqlite3_column_int(statement, 0)) }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Batches (1.2)

    private func createBatchesTable() {
        execute("""
            CREATE TABLE IF NOT EXISTS Batches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 0,
                price_base REAL NOT NULL,
                expiry_date TEXT,
                received_at TEXT NOT NULL,
                FOREIGN KEY(product_id) REFERENCES Products(id) ON DELETE CASCADE
            );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_batches_product ON Batches(product_id);")
        execute("CREATE INDEX IF NOT EXISTS idx_batches_expiry ON Batches(expiry_date);")
    }

    /// Corre uma vez: transforma o stock existente num lote inicial sem validade.
    /// Sem isto o stock antigo desaparecia no primeiro `syncProductStock`.
    private func migrateStockToBatches() {
        let sql = """
            SELECT id, stock, price_base FROM Products
            WHERE stock > 0 AND id NOT IN (SELECT DISTINCT product_id FROM Batches);
        """
        var statement: OpaquePointer?
        var pending: [(id: Int, stock: Int, priceBase: Double)] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        while sqlite3_step(statement) == SQLITE_ROW {
            pending.append((Int(sqlite3_column_int(statement, 0)),
                            Int(sqlite3_column_int(statement, 1)),
                            sqlite3_column_double(statement, 2)))
        }
        sqlite3_finalize(statement)

        for product in pending {
            _ = insertBatch(productId: product.id, quantity: product.stock,
                            priceBase: product.priceBase, expiryDate: nil, receivedAt: Date())
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    func fetchBatches(productId: Int) -> [Batch] {
        fetchBatches(sql: """
            SELECT id, product_id, quantity, price_base, expiry_date, received_at FROM Batches
            WHERE product_id = ? ORDER BY expiry_date IS NULL, expiry_date ASC, id ASC;
        """, productId: productId)
    }

    func fetchAllBatches() -> [Batch] {
        fetchBatches(sql: """
            SELECT id, product_id, quantity, price_base, expiry_date, received_at FROM Batches
            ORDER BY expiry_date IS NULL, expiry_date ASC, id ASC;
        """, productId: nil)
    }

    private func fetchBatches(sql: String, productId: Int?) -> [Batch] {
        var statement: OpaquePointer?
        var batches: [Batch] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        if let productId { sqlite3_bind_int(statement, 1, Int32(productId)) }
        while sqlite3_step(statement) == SQLITE_ROW {
            let expiryText = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            batches.append(Batch(
                id: Int(sqlite3_column_int(statement, 0)),
                productId: Int(sqlite3_column_int(statement, 1)),
                quantity: Int(sqlite3_column_int(statement, 2)),
                priceBase: sqlite3_column_double(statement, 3),
                expiryDate: expiryText.flatMap { Self.dayFormatter.date(from: $0) },
                receivedAt: ISO8601DateFormatter().date(from: String(cString: sqlite3_column_text(statement, 5))) ?? Date()
            ))
        }
        sqlite3_finalize(statement)
        return batches
    }

    @discardableResult
    func createBatch(productId: Int, quantity: Int, priceBase: Double, expiryDate: Date?, receivedAt: Date = Date()) -> Bool {
        guard quantity > 0, priceBase >= 0 else { return false }
        return transaction { () -> Bool? in
            guard insertBatch(productId: productId, quantity: quantity, priceBase: priceBase,
                              expiryDate: expiryDate, receivedAt: receivedAt) else { return nil }
            syncProductStock(productId: productId)
            return true
        } ?? false
    }

    /// Sem transação própria — usado dentro de transações maiores.
    @discardableResult
    private func insertBatch(productId: Int, quantity: Int, priceBase: Double, expiryDate: Date?, receivedAt: Date) -> Bool {
        let sql = "INSERT INTO Batches (product_id, quantity, price_base, expiry_date, received_at) VALUES (?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_int(statement, 1, Int32(productId))
        sqlite3_bind_int(statement, 2, Int32(quantity))
        sqlite3_bind_double(statement, 3, priceBase)
        if let expiryDate {
            sqlite3_bind_text(statement, 4, (Self.dayFormatter.string(from: expiryDate) as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_text(statement, 5, (ISO8601DateFormatter().string(from: receivedAt) as NSString).utf8String, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return result
    }

    func updateBatch(_ batch: Batch) -> Bool {
        guard batch.quantity >= 0, batch.priceBase >= 0 else { return false }
        return transaction { () -> Bool? in
            let sql = "UPDATE Batches SET quantity=?, price_base=?, expiry_date=? WHERE id=?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int(statement, 1, Int32(batch.quantity))
            sqlite3_bind_double(statement, 2, batch.priceBase)
            if let expiry = batch.expiryDate {
                sqlite3_bind_text(statement, 3, (Self.dayFormatter.string(from: expiry) as NSString).utf8String, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int(statement, 4, Int32(batch.id))
            let ok = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            guard ok else { return nil }
            syncProductStock(productId: batch.productId)
            return true
        } ?? false
    }

    func deleteBatch(id: Int) -> Bool {
        transaction { () -> Bool? in
            let productId = batchProductId(id)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM Batches WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int(statement, 1, Int32(id))
            let ok = sqlite3_step(statement) == SQLITE_DONE
            sqlite3_finalize(statement)
            guard ok else { return nil }
            if let productId { syncProductStock(productId: productId) }
            return true
        } ?? false
    }

    private func batchProductId(_ id: Int) -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT product_id FROM Batches WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int(statement, 1, Int32(id))
        var productId: Int? = nil
        if sqlite3_step(statement) == SQLITE_ROW { productId = Int(sqlite3_column_int(statement, 0)) }
        sqlite3_finalize(statement)
        return productId
    }

    /// Stock real de um produto = soma dos lotes.
    func availableStock(productId: Int) -> Int {
        let sql = "SELECT COALESCE(SUM(quantity), 0) FROM Batches WHERE product_id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_int(statement, 1, Int32(productId))
        var total = 0
        if sqlite3_step(statement) == SQLITE_ROW { total = Int(sqlite3_column_int(statement, 0)) }
        sqlite3_finalize(statement)
        return total
    }

    /// Stock **vendável**: exclui os lotes já fora do prazo. É este o valor que
    /// manda na venda — produto expirado não se vende.
    func sellableStock(productId: Int) -> Int {
        let sql = """
            SELECT COALESCE(SUM(quantity), 0) FROM Batches
            WHERE product_id = ? AND (expiry_date IS NULL OR expiry_date >= ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_int(statement, 1, Int32(productId))
        let today = Self.dayFormatter.string(from: Date()) as NSString
        sqlite3_bind_text(statement, 2, today.utf8String, -1, SQLITE_TRANSIENT)
        var total = 0
        if sqlite3_step(statement) == SQLITE_ROW { total = Int(sqlite3_column_int(statement, 0)) }
        sqlite3_finalize(statement)
        return total
    }

    /// `Products.stock` é só cache de leitura da soma dos lotes.
    func syncProductStock(productId: Int) {
        let sql = "UPDATE Products SET stock = (SELECT COALESCE(SUM(quantity), 0) FROM Batches WHERE product_id = ?) WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_int(statement, 1, Int32(productId))
        sqlite3_bind_int(statement, 2, Int32(productId))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    /// Consome stock por ordem de validade (mais próxima primeiro, sem validade por último).
    /// `excludeExpired` salta os lotes fora do prazo — é o que a venda usa.
    func consumeStockFIFO(productId: Int, quantity: Int, excludeExpired: Bool = false) -> Bool {
        transaction {
            consumeStockFIFOUnsafe(productId: productId, quantity: quantity, excludeExpired: excludeExpired) ? true : nil
        } ?? false
    }

    /// Sem transação própria — chamar apenas dentro de uma.
    private func consumeStockFIFOUnsafe(productId: Int, quantity: Int, excludeExpired: Bool = false) -> Bool {
        guard quantity > 0 else { return false }
        var remaining = quantity

        let candidates = excludeExpired
            ? fetchBatches(productId: productId).filter { $0.expiryStatus != .expired }
            : fetchBatches(productId: productId)

        for batch in candidates {
            if remaining == 0 { break }
            let take = min(batch.quantity, remaining)
            guard take > 0 else { continue }

            if take == batch.quantity {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "DELETE FROM Batches WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return false }
                sqlite3_bind_int(statement, 1, Int32(batch.id))
                let ok = sqlite3_step(statement) == SQLITE_DONE
                sqlite3_finalize(statement)
                guard ok else { return false }
            } else {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE Batches SET quantity = quantity - ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return false }
                sqlite3_bind_int(statement, 1, Int32(take))
                sqlite3_bind_int(statement, 2, Int32(batch.id))
                let ok = sqlite3_step(statement) == SQLITE_DONE
                sqlite3_finalize(statement)
                guard ok else { return false }
            }
            remaining -= take
        }

        guard remaining == 0 else { return false }   // stock insuficiente → ROLLBACK
        syncProductStock(productId: productId)
        return true
    }

    /// Leva o stock de um produto até `newStock` mexendo nos lotes.
    /// Aumento vai para o lote sem validade (cria-o se não existir); redução usa FIFO.
    private func adjustStockToBatches(productId: Int, newStock: Int) -> Bool {
        let current = availableStock(productId: productId)
        let delta = newStock - current

        if delta < 0 {
            guard consumeStockFIFOUnsafe(productId: productId, quantity: -delta) else { return false }
            return true
        }
        if delta > 0 {
            let openBatch = fetchBatches(productId: productId).first { $0.expiryDate == nil }
            if let openBatch {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE Batches SET quantity = quantity + ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return false }
                sqlite3_bind_int(statement, 1, Int32(delta))
                sqlite3_bind_int(statement, 2, Int32(openBatch.id))
                let ok = sqlite3_step(statement) == SQLITE_DONE
                sqlite3_finalize(statement)
                guard ok else { return false }
            } else {
                let priceBase = fetchProduct(id: productId)?.priceBase ?? 0
                guard insertBatch(productId: productId, quantity: delta, priceBase: priceBase,
                                  expiryDate: nil, receivedAt: Date()) else { return false }
            }
        }
        syncProductStock(productId: productId)
        return true
    }
}
