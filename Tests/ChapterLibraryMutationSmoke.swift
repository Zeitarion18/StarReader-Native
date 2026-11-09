import Foundation

@main
enum ChapterLibraryMutationSmoke {
    static func main() throws {
        let baseParagraphs = [
            ChapterLibraryMutation.Paragraph(
                text: "Зейт и Лиара встретили рассвет.",
                heading: false
            ),
            ChapterLibraryMutation.Paragraph(
                text: "Продолжение истории.",
                heading: false
            )
        ]
        func add(
            to data: Data?,
            id: String,
            volume: String = "Том 15",
            title: String = "Пролог",
            allowDuplicate: Bool = false
        ) throws -> Data {
            try ChapterLibraryMutation.append(
                to: data,
                series: "Связь сохранена",
                volume: volume,
                title: title,
                paragraphs: baseParagraphs,
                chapterID: id,
                originalFile: "native-" + id + ".docx",
                allowDuplicate: allowDuplicate
            )
        }
        func object(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        func books(_ library: [String: Any]) -> [[String: Any]] {
            library["books"] as! [[String: Any]]
        }

        let first = try add(to: nil, id: "one")
        let firstJSON = try object(first)
        precondition((firstJSON["schema"] as? Int) == 2)
        precondition((firstJSON["works"] as? [String]) == ["Связь сохранена"])
        precondition((firstJSON["volumes"] as! [[String: Any]]).count == 1)
        precondition(books(firstJSON).count == 1)
        precondition((books(firstJSON)[0]["paragraphs"] as! [[String: Any]]).count == 2)

        do {
            _ = try add(to: first, id: "two")
            preconditionFailure("Duplicate title must be blocked")
        } catch ChapterLibraryMutation.Failure.duplicateChapter {
            // Correct: no implicit overwrite.
        }
        let second = try add(to: first, id: "two", allowDuplicate: true)
        let secondJSON = try object(second)
        precondition(books(secondJSON).count == 2)
        precondition(books(secondJSON).map { $0["id"] as! String } == ["one", "two"])

        let third = try add(to: second, id: "three", volume: "Том 16")
        let thirdJSON = try object(third)
        precondition((thirdJSON["volumes"] as! [[String: Any]]).count == 2)
        precondition(books(thirdJSON).count == 3)
        precondition((thirdJSON["works"] as! [String]).count == 1)

        var metadata = thirdJSON
        metadata["trash"] = [["id": "older-chapter"]]
        metadata["customField"] = ["remember": true]
        let dataWithMetadata = try JSONSerialization.data(withJSONObject: metadata)
        let fourth = try add(
            to: dataWithMetadata, id: "four", title: "Глава 1"
        )
        let fourthJSON = try object(fourth)
        precondition((fourthJSON["trash"] as! [[String: Any]]).count == 1)
        precondition((fourthJSON["customField"] as! [String: Bool])["remember"] == true)
        precondition(books(fourthJSON).count == 4)

        do {
            _ = try add(to: fourth, id: "one", title: "Глава 2")
            preconditionFailure("Duplicate IDs must be blocked")
        } catch ChapterLibraryMutation.Failure.duplicateID {
            // Correct.
        }

        do {
            let broken = Data("{\"schema\":7}".utf8)
            _ = try add(to: broken, id: "five", title: "Глава 5")
            preconditionFailure("Corrupted library must be blocked")
        } catch ChapterLibraryMutation.Failure.invalidLibrary {
            // Correct.
        }

        print("PASS: first import, new volume, duplicate-title consent, " +
              "duplicate IDs, metadata preservation and invalid JSON.")
    }
}
