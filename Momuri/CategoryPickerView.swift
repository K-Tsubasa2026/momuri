import SwiftUI

struct CategoryPickerView: View {
    let onPick: (RoutineCategory) -> Void
    var onJoined: () -> Void = {}
    @State private var joining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("어떤 루틴인가요?").font(.title2.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(RoutineCategory.allCases, id: \.self) { category in
                        Button { onPick(category) } label: { card(category) }
                            .buttonStyle(.plain)
                            .disabled(!category.isAvailable)
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $joining) { JoinShareView(onJoined: onJoined) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { joining = true } label: {
                    Label("코드로 참여", systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("새 루틴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ category: RoutineCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: category.symbol).font(.title3)
                Spacer()
                if !category.isAvailable {
                    Text("곧")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3)))
                }
            }
            Spacer(minLength: 0)
            Text(category.title).font(.headline)
            Text(category.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
        .opacity(category.isAvailable ? 1 : 0.4)
    }
}
