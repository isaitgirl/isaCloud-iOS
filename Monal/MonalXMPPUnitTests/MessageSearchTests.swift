//
//  MessageSearchTests.swift
//  MonalXMPPUnitTests
//
//  isaCloud: full text search in the messages: what is typed becomes a safe FTS5 query, the index finds words
//  (prefix, no matter accents or case), leaves out what must not be found, and follows the changes of the messages.
//

import Foundation
import Testing
import monalxmpp

struct MessageSearchTests {

    // MARK: the build

    @Test("the SQLite of this build has FTS5 (a stale compiled SQLite loses it without any warning)")
    func sqliteHasFTS5() {
        #expect(MLMessageSearch.isAvailable())
    }

    // MARK: the query

    @Test("every word becomes a prefix in quotes, all of them are needed")
    func queryWords() {
        #expect(MLMessageSearch.matchString(forQuery: "lula") == "\"lula\"*")
        #expect(MLMessageSearch.matchString(forQuery: "  reunião   amanhã \n") == "\"reunião\"* \"amanhã\"*")
    }

    @Test("FTS5 syntax typed by the person is just text")
    func queryIsSafe() {
        #expect(MLMessageSearch.matchString(forQuery: "foo AND bar OR NOT baz*") == "\"foo\"* \"AND\"* \"bar\"* \"OR\"* \"NOT\"* \"baz*\"*")
        #expect(MLMessageSearch.matchString(forQuery: "a\"b") == "\"a\"\"b\"*")
        #expect(MLMessageSearch.matchString(forQuery: "col:val NEAR(a b)") == "\"col:val\"* \"NEAR(a\"* \"b)\"*")
    }

    @Test("nothing to look for gives no query")
    func queryEmpty() {
        #expect(MLMessageSearch.matchString(forQuery: "") == nil)
        #expect(MLMessageSearch.matchString(forQuery: "   ") == nil)
        #expect(MLMessageSearch.matchString(forQuery: "? ! \" -") == nil)
    }

    // MARK: the index

    /// a database with the tables the search reads, and the messages given as (text, type, account, retracted)
    private func makeDatabase(_ messages: [(String, String, Int, Bool)] = []) -> MLSQLite {
        let path = NSTemporaryDirectory() + "search-\(UUID().uuidString).sqlite"
        let db = MLSQLite.sharedInstance(forFile: path) as! MLSQLite
        db.voidWriteTransaction {
            db.executeNonQuery("CREATE TABLE flags (name VARCHAR(32) NOT NULL PRIMARY KEY, value TEXT DEFAULT NULL);")
            db.executeNonQuery("CREATE TABLE account (account_id INTEGER PRIMARY KEY, enabled BOOL DEFAULT 1);")
            db.executeNonQuery("INSERT INTO account (account_id, enabled) VALUES (1, 1), (2, 0);")
            db.executeNonQuery("CREATE TABLE message_history (message_history_id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INTEGER NOT NULL, buddy_name TEXT NOT NULL, inbound BOOL DEFAULT 0, unread BOOL DEFAULT 0, timestamp DATETIME NOT NULL, message BLOB NOT NULL, messageType TEXT, retracted BOOL DEFAULT 0);")
        }
        for (index, message) in messages.enumerated() {
            insert(db, text: message.0, type: message.1, account: message.2, retracted: message.3, day: index + 1)
        }
        return db
    }

    @discardableResult
    private func insert(_ db: MLSQLite, text: String, type: String = "Text", account: Int = 1, retracted: Bool = false, day: Int, id: Int? = nil) -> Int {
        var newId = 0
        db.voidWriteTransaction {
            let timestamp = String(format: "2026-10-%02d 12:00:00", day)
            if let id = id {
                db.executeNonQuery("INSERT INTO message_history (message_history_id, account_id, buddy_name, timestamp, message, messageType, retracted) VALUES (?, ?, 'amiga@example.org', ?, ?, ?, ?);", andArguments: [id, account, timestamp, text, type, retracted ? 1 : 0])
            } else {
                db.executeNonQuery("INSERT INTO message_history (account_id, buddy_name, timestamp, message, messageType, retracted) VALUES (?, 'amiga@example.org', ?, ?, ?, ?);", andArguments: [account, timestamp, text, type, retracted ? 1 : 0])
            }
            newId = (db.lastInsertId() as NSNumber).intValue
        }
        return newId
    }

    private func buildIndex(_ db: MLSQLite) {
        db.voidWriteTransaction { MLMessageSearch.createIndex(inDatabase: db) }
    }

    private func search(_ db: MLSQLite, _ query: String, limit: Int = 50, offset: Int = 0) -> [Int] {
        let ids = db.idReadTransaction { MLMessageSearch.historyIds(matchingQuery: query, limit: UInt(limit), offset: UInt(offset), inDatabase: db) } as! [NSNumber]
        return ids.map { $0.intValue }
    }

    @Test("finds words by prefix, whatever the accents and the case")
    func findsWords() {
        let db = makeDatabase([("Ação e coração", "Text", 1, false), ("lula ganhou a eleição", "Text", 1, false), ("nada a ver", "Text", 1, false)])
        buildIndex(db)
        #expect(search(db, "acao") == [1])
        #expect(search(db, "CORAÇÃO") == [1])
        #expect(search(db, "lul") == [2])
        #expect(search(db, "eleicao") == [2])
        #expect(search(db, "xyz").isEmpty)
    }

    @Test("every word of the query is needed, in any order")
    func needsEveryWord() {
        let db = makeDatabase([("reunião amanhã cedo", "Text", 1, false), ("reunião adiada", "Text", 1, false)])
        buildIndex(db)
        #expect(search(db, "reuniao") == [2, 1])
        #expect(search(db, "amanha reuniao") == [1])
        #expect(search(db, "cedo amanha") == [1])
        #expect(search(db, "reuniao cancelada").isEmpty)
    }

    @Test("newest first, in pages")
    func newestFirstAndPages() {
        let db = makeDatabase((1...5).map { ("bom dia \($0)", "Text", 1, false) })
        buildIndex(db)
        #expect(search(db, "bom") == [5, 4, 3, 2, 1])
        #expect(search(db, "bom", limit: 2) == [5, 4])
        #expect(search(db, "bom", limit: 2, offset: 2) == [3, 2])
        #expect(search(db, "bom", limit: 2, offset: 4) == [1])
    }

    @Test("files, retracted messages and messages of disabled accounts are never found, links are")
    func leavesOutWhatMustNotBeFound() {
        let db = makeDatabase([
            ("aesgcm://example.org/file.jpg#0123456789abcdef", "Filetransfer", 1, false),
            ("texto retirado", "Text", 1, true),
            ("texto de conta desligada", "Text", 2, false),
            ("https://example.org/pagina", "Url", 1, false),
            ("texto normal", "Text", 1, false),
        ])
        buildIndex(db)
        #expect(search(db, "aesgcm").isEmpty)
        #expect(search(db, "0123456789abcdef").isEmpty)
        #expect(search(db, "retirado").isEmpty)
        #expect(search(db, "desligada").isEmpty)
        #expect(search(db, "pagina") == [4])
        #expect(search(db, "texto") == [5])
    }

    @Test("what is typed can never break the query")
    func typedTextNeverBreaks() {
        let db = makeDatabase([("foo bar", "Text", 1, false)])
        buildIndex(db)
        for query in ["\"", "foo AND", "NOT", "foo*", "col:val", "NEAR(", "( )", "-foo", "'; DROP TABLE message_history; --"] {
            _ = search(db, query)
        }
        #expect(search(db, "foo") == [1])
    }

    // MARK: following the messages

    @Test("an edit replaces the words, a retraction and a deletion remove them")
    func followsChanges() {
        let db = makeDatabase([("primeira versão", "Text", 1, false), ("outra mensagem", "Text", 1, false), ("mais uma", "Text", 1, false)])
        buildIndex(db)

        db.voidWriteTransaction {
            db.executeNonQuery("UPDATE message_history SET message='segunda versão' WHERE message_history_id=1;")
            MLMessageSearch.updateIndex(forHistoryId: 1, inDatabase: db)
        }
        #expect(search(db, "primeira").isEmpty)
        #expect(search(db, "segunda") == [1])

        db.voidWriteTransaction {
            db.executeNonQuery("UPDATE message_history SET message='', retracted=1 WHERE message_history_id=2;")
            MLMessageSearch.updateIndex(forHistoryId: 2, inDatabase: db)
        }
        #expect(search(db, "outra").isEmpty)

        db.voidWriteTransaction {
            db.executeNonQuery("DELETE FROM message_history WHERE message_history_id=3;")
            MLMessageSearch.updateIndex(forHistoryId: 3, inDatabase: db)
        }
        #expect(search(db, "mais uma").isEmpty)
        #expect(ftsRows(db) == 1)
    }

    @Test("a message indexed as new is found, and a file or a retracted one is not")
    func indexesNewMessages() {
        let db = makeDatabase([("mensagem que já existia", "Text", 1, false)])
        buildIndex(db)
        let text = insert(db, text: "chegou agora", day: 5)
        let file = insert(db, text: "aesgcm://example.org/chegou.jpg#chave", type: "Filetransfer", day: 6)
        let negative = insert(db, text: "chegou do arquivo do servidor", day: 2, id: -3)
        db.voidWriteTransaction {
            for id in [text, file, negative] { MLMessageSearch.indexNewMessage(withHistoryId: NSNumber(value: id), inDatabase: db) }
        }
        #expect(search(db, "chegou") == [text, negative])
        #expect(ftsRows(db) == 3)
    }

    @Test("a text message that turns into a file is no longer found")
    func turnsIntoFile() {
        let db = makeDatabase([("https://example.org/imagem.jpg", "Text", 1, false)])
        buildIndex(db)
        #expect(search(db, "imagem") == [1])
        db.voidWriteTransaction {
            db.executeNonQuery("UPDATE message_history SET messageType='Filetransfer' WHERE message_history_id=1;")
            MLMessageSearch.updateIndex(forHistoryId: 1, inDatabase: db)
        }
        #expect(search(db, "imagem").isEmpty)
    }

    @Test("removing messages in bulk takes their words out of the index")
    func removesInBulk() {
        let db = makeDatabase([("conversa da ana", "Text", 1, false), ("conversa do bia", "Text", 1, false)])
        db.voidWriteTransaction { db.executeNonQuery("UPDATE message_history SET buddy_name='bia@example.org' WHERE message_history_id=2;") }
        buildIndex(db)
        db.voidWriteTransaction {
            MLMessageSearch.remove(fromIndexMessagesWhere: "buddy_name=?", arguments: ["bia@example.org"], inDatabase: db)
            db.executeNonQuery("DELETE FROM message_history WHERE buddy_name='bia@example.org';")
        }
        #expect(search(db, "conversa") == [1])
        #expect(ftsRows(db) == 1)
    }

    @Test("the catch up indexes what the hooks did not see, above and below what was indexed")
    func catchUp() {
        let db = makeDatabase([("antiga mensagem", "Text", 1, false)])
        buildIndex(db)
        //written without the hooks: a newer message, and one loaded backwards from the server archive (negative id)
        insert(db, text: "mensagem nova sem gancho", day: 10)
        insert(db, text: "mensagem de arquivo antigo", day: 1, id: -5)
        #expect(search(db, "gancho").isEmpty)
        #expect(search(db, "arquivo").isEmpty)
        db.voidWriteTransaction { MLMessageSearch.catchUpIndex(inDatabase: db) }
        #expect(search(db, "gancho") != [])
        #expect(search(db, "arquivo") == [-5])
        #expect(search(db, "mensagem").count == 3)
        //a second catch up changes nothing (and does not trip over rows the hooks already indexed)
        db.voidWriteTransaction { MLMessageSearch.catchUpIndex(inDatabase: db) }
        #expect(search(db, "mensagem").count == 3)
        #expect(ftsRows(db) == 3)
    }

    @Test("the catch up forgets messages that were deleted behind its back")
    func catchUpForgetsDeleted() {
        let db = makeDatabase([("vai sumir", "Text", 1, false), ("fica", "Text", 1, false)])
        buildIndex(db)
        db.voidWriteTransaction { db.executeNonQuery("DELETE FROM message_history WHERE message_history_id=1;") }
        #expect(ftsRows(db) == 2)
        //the purge runs at most once a day: make it due
        db.voidWriteTransaction {
            db.executeNonQuery("DELETE FROM flags WHERE name='isacloud_search_purged_at';")
            MLMessageSearch.catchUpIndex(inDatabase: db)
        }
        #expect(ftsRows(db) == 1)
        #expect(search(db, "sumir").isEmpty)
    }

    private func ftsRows(_ db: MLSQLite) -> Int {
        (db.idReadTransaction { db.executeScalar("SELECT count(*) FROM message_search;") } as! NSNumber).intValue
    }
}
