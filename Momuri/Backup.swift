import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 기록 전체를 JSON 파일 하나로 내보내고 불러온다.
/// 자동 백업은 앱 문서 폴더에 하루 한 번 (파일 앱 > 나의 iPhone > momuri 에서 보임).
@MainActor
enum Backup {
    struct File: Codable {
        var version = 1
        var exportedAt = Date()
        var routines: [RoutineData]
    }

    struct RoutineData: Codable {
        var id: UUID
        var definition: RoutineDefinition
        var sortOrder: Int
        var createdAt: Date
        var isCritical: Bool
        var useAlarm: Bool
        var restWeekdays: [Int]
        var showInWidget: Bool
        var showLive: Bool
        var autoHealth: Bool
        var shareId: String?
        var shareCode: String?
        var shareOwner: Bool
        var logs: [LogData]
    }

    struct LogData: Codable {
        var id: UUID
        var date: Date
        var value: Double?
        var part: String?
        var externalID: String?
        var skipped: Bool
        var sets: [SetData]
    }

    struct SetData: Codable {
        var exercise: String
        var weight: Double
        var reps: Int
        var order: Int
    }

    static func makeFile(context: ModelContext) -> File {
        let routines = (try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        return File(routines: routines.map { r in
            RoutineData(
                id: r.id, definition: RoutineDefinition(r), sortOrder: r.sortOrder, createdAt: r.createdAt,
                isCritical: r.isCritical, useAlarm: r.useAlarm, restWeekdays: r.restWeekdays,
                showInWidget: r.showInWidget, showLive: r.showLive, autoHealth: r.autoHealth,
                shareId: r.shareId, shareCode: r.shareCode, shareOwner: r.shareOwner,
                logs: (r.logs ?? []).map { l in
                    LogData(id: l.id, date: l.date, value: l.value, part: l.part, externalID: l.externalID, skipped: l.skipped,
                            sets: (l.sets ?? []).map { SetData(exercise: $0.exercise, weight: $0.weight, reps: $0.reps, order: $0.order) })
                }
            )
        })
    }

    static func encode(_ file: File) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// 지금 기록을 모두 지우고 백업으로 바꾼다
    static func restore(_ data: Data, context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        try context.delete(model: WorkoutSet.self)
        try context.delete(model: RoutineLog.self)
        try context.delete(model: Routine.self)
        for item in file.routines {
            let r = Routine(name: item.definition.name, kind: .daily, sortOrder: item.sortOrder)
            item.definition.apply(to: r)
            r.id = item.id
            r.createdAt = item.createdAt
            r.isCritical = item.isCritical
            r.useAlarm = item.useAlarm
            r.restWeekdays = item.restWeekdays
            r.showInWidget = item.showInWidget
            r.showLive = item.showLive
            r.autoHealth = item.autoHealth
            r.shareId = item.shareId
            r.shareCode = item.shareCode
            r.shareOwner = item.shareOwner
            context.insert(r)
            for l in item.logs {
                let log = RoutineLog(date: l.date, value: l.value, part: l.part)
                log.id = l.id
                log.externalID = l.externalID
                log.skipped = l.skipped
                context.insert(log)
                r.logs?.append(log)
                for s in l.sets {
                    let set = WorkoutSet(exercise: s.exercise, weight: s.weight, reps: s.reps, order: s.order)
                    context.insert(set)
                    log.sets?.append(set)
                }
            }
        }
        RoutineActions.commit(context)
        return file.routines.count
    }

    // MARK: - 자동 백업

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "백업")
    }

    /// 하루 한 번, 최근 14개만 남긴다
    static func autoBackupIfNeeded(context: ModelContext) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = folder.appending(path: "momuri-\(f.string(from: .now)).json")
        guard !fm.fileExists(atPath: url.path()),
              let data = try? encode(makeFile(context: context)) else { return }
        try? data.write(to: url, options: .atomic)
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(14) { try? fm.removeItem(at: old) }
    }

    static var lastAutoBackup: String? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.map(\.lastPathComponent).filter { $0.hasSuffix(".json") }.max()?
            .replacingOccurrences(of: "momuri-", with: "").replacingOccurrences(of: ".json", with: "")
    }
}

/// 내보내기용 문서
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// 설정 시트: 백업 내보내기·불러오기
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var exportDoc: BackupDocument?
    @State private var importing = false
    @State private var pendingRestore: Data?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("백업 파일 내보내기") {
                        if let data = try? Backup.encode(Backup.makeFile(context: context)) { exportDoc = BackupDocument(data: data) }
                    }
                    Button("백업 파일 불러오기") { importing = true }
                } header: {
                    Text("백업")
                } footer: {
                    Text("자동 백업: 하루 한 번 파일 앱 > 나의 iPhone > momuri > 백업 에 저장돼요 (최근 14일)."
                         + (Backup.lastAutoBackup.map { "\n마지막 자동 백업 \($0)" } ?? ""))
                }
                if let message {
                    Section { Text(message).font(.subheadline) }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                          document: exportDoc, contentType: .json,
                          defaultFilename: "momuri-backup") { result in
                if case .success = result { message = "백업 파일을 저장했어요." }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingRestore = try? Data(contentsOf: url)
            }
            .confirmationDialog("지금 기록을 모두 지우고 백업으로 바꿀까요?",
                                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                                titleVisibility: .visible) {
                Button("바꾸기", role: .destructive) {
                    guard let data = pendingRestore else { return }
                    do {
                        let n = try Backup.restore(data, context: context)
                        message = "루틴 \(n)개를 불러왔어요."
                    } catch {
                        message = "momuri 백업 파일이 아니에요."
                    }
                }
            }
        }
        .tint(.primary)
    }
}
