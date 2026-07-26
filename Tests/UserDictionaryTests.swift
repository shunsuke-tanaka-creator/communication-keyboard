// UserDictionaryTests.swift
// MozcFlickKeyboard — ユーザー辞書（UserDictionaryStore）の単体テスト。
//
// 結合後の実 API に合わせて調整済み:
//  - UserDictionaryStore(baseURL:) でテスト用の一時ディレクトリへ永続化（App Group 不要）
//  - add(reading:word:partOfSpeech:) throws / entries(forExactReading:) / setEnabled / removeAll
//  - DictionaryImportExport.exportCSV/importCSV/exportJSON/importJSON
// 重複ポリシー: 同一 reading(正規化)+word は duplicateEntry エラー。
// 完全一致検索は既定 enabledOnly=true（無効項目は除外）。

import XCTest
@testable import MozcFlickShared

final class UserDictionaryTests: XCTestCase {

    private var store: UserDictionaryStore!
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserDictTests-\(UUID().uuidString)", isDirectory: true)
        store = try UserDictionaryStore(baseURL: tempDir)
    }

    override func tearDownWithError() throws {
        store = nil
        if let dir = tempDir { try? FileManager.default.removeItem(at: dir) }
        tempDir = nil
        try super.tearDownWithError()
    }

    /// テスト用の別ストア（独立ディレクトリ）を作る。
    private func makeStore() throws -> UserDictionaryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserDictTests-\(UUID().uuidString)", isDirectory: true)
        return try UserDictionaryStore(baseURL: dir)
    }

    // MARK: - 登録と読みからの候補取得

    func testAddAndLookup() throws {
        try store.add(reading: "くぼたけん", word: "久保田研", partOfSpeech: .placeName)
        let cands = store.entries(forExactReading: "くぼたけん")
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands.first?.word, "久保田研")
        XCTAssertEqual(cands.first?.partOfSpeech, .placeName)
    }

    func testLookupUnknownReading() {
        XCTAssertTrue(store.entries(forExactReading: "そんざいしない").isEmpty)
    }

    // MARK: - 重複（同一 reading+word は duplicateEntry）

    func testDuplicateReadingAndWordThrows() throws {
        try store.add(reading: "もずく", word: "Mozc", partOfSpeech: .noun)
        XCTAssertThrowsError(try store.add(reading: "もずく", word: "Mozc", partOfSpeech: .noun))
        XCTAssertEqual(store.entries(forExactReading: "もずく").count, 1)
    }

    func testSameReadingDifferentWordCoexist() throws {
        try store.add(reading: "きょう", word: "教", partOfSpeech: .noun)
        try store.add(reading: "きょう", word: "京", partOfSpeech: .placeName)
        let cands = store.entries(forExactReading: "きょう")
        XCTAssertEqual(cands.count, 2)
        XCTAssertEqual(Set(cands.map { $0.word }), ["教", "京"])
    }

    // MARK: - 削除

    func testRemove() throws {
        let e = try store.add(reading: "さくじょ", word: "削除", partOfSpeech: .noun)
        XCTAssertEqual(store.entries(forExactReading: "さくじょ").count, 1)
        try store.remove(id: e.id)
        XCTAssertTrue(store.entries(forExactReading: "さくじょ").isEmpty)
    }

    // MARK: - 無効化（isEnabled=false は候補から除外されるが保持される）

    func testDisableExcludesFromCandidates() throws {
        let e = try store.add(reading: "むこう", word: "無効", partOfSpeech: .noun)
        try store.setEnabled(id: e.id, isEnabled: false)
        XCTAssertTrue(store.entries(forExactReading: "むこう").isEmpty, "無効項目は候補から除外されるべき")
        XCTAssertTrue(store.allEntries().contains(where: { $0.id == e.id }), "無効化しても項目は保持されるべき")
    }

    // MARK: - CSV 入出力

    func testCSVRoundTrip() throws {
        try store.add(reading: "くぼた", word: "久保田", partOfSpeech: .personName)
        try store.add(reading: "けんきゅう", word: "研究", partOfSpeech: .noun)
        let csv = DictionaryImportExport.exportCSV(entries: store.allEntries())

        let other = try makeStore()
        _ = try DictionaryImportExport.importCSV(csv, into: other)
        XCTAssertEqual(other.entries(forExactReading: "くぼた").first?.word, "久保田")
        XCTAssertEqual(other.entries(forExactReading: "けんきゅう").first?.word, "研究")
    }

    // MARK: - JSON 入出力

    func testJSONRoundTrip() throws {
        try store.add(reading: "でーた", word: "データ", partOfSpeech: .noun)
        let data = try DictionaryImportExport.exportJSON(entries: store.allEntries())

        let other = try makeStore()
        _ = try DictionaryImportExport.importJSON(data, into: other)
        XCTAssertEqual(other.entries(forExactReading: "でーた").first?.word, "データ")
    }

    // MARK: - 性能（100 / 1000 / 10000 件）

    func testPerformanceInsert100() throws {
        measure {
            guard let s = try? makeStore() else { return }
            for i in 0..<100 {
                try? s.add(reading: "よみ\(i)", word: "語\(i)", partOfSpeech: .noun)
            }
        }
    }

    func testPerformanceLookupIn1000() throws {
        let s = try makeStore()
        for i in 0..<1000 {
            try s.add(reading: "よみ\(i)", word: "語\(i)", partOfSpeech: .noun)
        }
        measure {
            _ = s.entries(forExactReading: "よみ999")
        }
    }

    func testPerformanceLookupIn10000() throws {
        let s = try makeStore()
        for i in 0..<10000 {
            try s.add(reading: "よみ\(i)", word: "語\(i)", partOfSpeech: .noun)
        }
        XCTAssertEqual(s.allEntries().count, 10000)
        measure {
            _ = s.entries(forExactReading: "よみ9999")
        }
    }
}
