import Foundation

@main
enum LibraryDeletionSmoke {
    static func main() throws {
        let original: [String: Any] = [
            "schema": 2,
            "works": ["Сказание"],
            "volumes": [
                ["series": "Сказание", "title": "Том 1"],
                ["series": "Сказание", "title": "Том 2"],
                ["series": "Сказание", "title": "Пустой том"]
            ],
            "books": [
                ["id": "a", "series": "Сказание", "volume": "Том 1",
                 "chapter": "Пролог", "paragraphs": [["text": "Первый"]]],
                ["id": "b", "series": "Сказание", "volume": "Том 1",
                 "chapter": "Пролог", "paragraphs": [["text": "Второй"]]],
                ["id": "c", "series": "Сказание", "volume": "Том 2",
                 "chapter": "Глава 1", "paragraphs": [["text": "Третий"]]]
            ],
            "trash": [["id": "old-trash"]],
            "extraLibraryKey": ["preserve": 42]
        ]
        let state: [String: Any] = [
            "schema": 1,
            "progress": ["a": ["para": 0], "b": ["para": 1],
                         "c": ["para": 2], "old-orphan": ["para": 3]],
            "annotations": [
                ["bookId": "a", "note": "a-note"],
                ["bookId": "b", "note": "b-note"],
                ["bookId": "c", "note": "c-note"],
                ["bookId": "old-orphan", "note": "orphan-note"]
            ],
            "bookmarks": [
                ["bookId": "a"], ["bookId": "b"],
                ["bookId": "c"], ["bookId": "old-orphan"]
            ],
            "settings": ["theme": "night"],
            "extraStateKey": "retain this"
        ]
        func bytes(_ object: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: object)
        }
        func dict(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        func bookIDs(_ library: [String: Any]) -> [String] {
            (library["books"] as! [[String: Any]]).compactMap { $0["id"] as? String }
        }
        let libraryData = try bytes(original)
        let stateData = try bytes(state)
        let single = try LibraryDeletion.remove(
            .chapter(id: "a"), from: libraryData, stateData: stateData
        )
        let afterSingle = try dict(single.libraryData)
        let afterSingleState = try dict(single.stateData)
        precondition(bookIDs(afterSingle) == ["b", "c"])
        precondition(single.deletedChapters == 1)
        precondition((afterSingle["trash"] as! [[String: Any]]).count == 1)
        precondition((afterSingle["extraLibraryKey"] as! [String: Int])["preserve"] == 42)
        precondition((afterSingleState["progress"] as! [String: Any])["a"] == nil)
        precondition((afterSingleState["progress"] as! [String: Any])["b"] != nil)
        precondition((afterSingleState["progress"] as! [String: Any])["old-orphan"] != nil)
        precondition((afterSingleState["annotations"] as! [[String: Any]]).count == 3)
        precondition((afterSingleState["bookmarks"] as! [[String: Any]]).count == 3)
        precondition(afterSingleState["extraStateKey"] as? String == "retain this")

        let volume = try LibraryDeletion.remove(
            .volume(series: "Сказание", title: "Том 1"),
            from: libraryData, stateData: stateData
        )
        let afterVolume = try dict(volume.libraryData)
        let afterVolumeState = try dict(volume.stateData)
        precondition(bookIDs(afterVolume) == ["c"])
        precondition(volume.deletedIDs == Set(["a", "b"]))
        precondition(volume.deletedChapters == 2)
        precondition((afterVolume["volumes"] as! [[String: Any]]).count == 2)
        precondition((afterVolume["works"] as! [String]) == ["Сказание"])
        precondition((afterVolumeState["progress"] as! [String: Any])["c"] != nil)
        precondition((afterVolumeState["progress"] as! [String: Any])["a"] == nil)
        precondition((afterVolumeState["annotations"] as! [[String: Any]]).count == 2)
        precondition((afterVolumeState["bookmarks"] as! [[String: Any]]).count == 2)

        let empty = try LibraryDeletion.remove(
            .volume(series: "Сказание", title: "Пустой том"),
            from: libraryData, stateData: stateData
        )
        precondition(empty.deletedIDs.isEmpty)
        precondition(bookIDs(try dict(empty.libraryData)) == ["a", "b", "c"])
        precondition((try dict(empty.libraryData)["volumes"] as! [[String: Any]]).count == 2)

        do {
            _ = try LibraryDeletion.remove(
                .chapter(id: "missing"), from: libraryData, stateData: stateData
            )
            preconditionFailure("Nonexistent chapter was deleted")
        } catch LibraryDeletion.Failure.notFound {
            // Expected.
        }
        precondition((try dict(libraryData))["books"] != nil)
        print("PASS: single duplicate title, entire volume, empty volume, " +
              "related records, orphan preservation, unknown fields, missing target.")
    }
}
