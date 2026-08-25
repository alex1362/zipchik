import Foundation
import Testing
@testable import ZIPApp

@Test func allowsRelativeArchivePaths() {
    #expect(ArchivePath.isSafe("folder/file.txt"))
}

@Test func rejectsTraversalAndAbsolutePaths() {
    #expect(!ArchivePath.isSafe("../file.txt"))
    #expect(!ArchivePath.isSafe("/etc/passwd"))
    #expect(!ArchivePath.isSafe("folder/../../file.txt"))
}

@Test func recognizesFirstPartOfMultiVolumeArchive() {
    #expect(ArchiveVolume.isFirstPart(URL(fileURLWithPath: "/tmp/archive.7z.001")))
    #expect(!ArchiveVolume.isFirstPart(URL(fileURLWithPath: "/tmp/archive.7z.002")))
    #expect(!ArchiveVolume.isFirstPart(URL(fileURLWithPath: "/tmp/document.001")))
}

@Test func archiveOperationRecordsCancellation() {
    let operation = ArchiveOperation()
    #expect(!operation.isCancelled)
    operation.cancel()
    #expect(operation.isCancelled)
}

@Test func archiveOperationTerminatesAttachedProcess() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["10"]
    try process.run()

    let operation = ArchiveOperation()
    operation.attach(process)
    operation.cancel()
    process.waitUntilExit()

    #expect(operation.isCancelled)
    #expect(process.terminationStatus != 0)
}
