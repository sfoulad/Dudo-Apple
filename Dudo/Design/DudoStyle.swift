import SwiftUI

/// The small set of visual decisions the Customer Directory is built from.
///
/// Dudo's identity comes from its app icon: a scarlet macaw on a deep navy field. The
/// interface uses exactly those two colours and nothing else — navy carries identity, scarlet
/// is the single accent, and everything else is system material so that the app looks like it
/// belongs on each platform rather than like a web page in a window.
enum DudoStyle {
    /// `#071342` in light, lifted for legibility in dark. Identity, and the fill behind a
    /// customer's initials.
    static let navy = Color("BrandNavy")
    /// The macaw's scarlet. Also the app's accent colour, so it appears on every control tint
    /// without being applied by hand.
    static let scarlet = Color("BrandScarlet")

    enum Space {
        static let row: CGFloat = 12
        static let section: CGFloat = 20
        static let card: CGFloat = 16
    }
}

// MARK: - Initials

/// A customer's initials on a navy disc.
///
/// Deliberately not a photograph, a logo or a generated illustration: Dudo holds no such data
/// about a customer, and an interface that shows one would be showing something the record
/// does not contain.
struct CustomerAvatar: View {
    let name: String
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().fill(DudoStyle.navy)
            Text(Self.initials(from: name))
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// One initial for a person, two for a company that has two words. Falls back to a symbol
    /// character rather than an empty disc for a name with no letters in it.
    static func initials(from name: String) -> String {
        let words = name
            .split(whereSeparator: \.isWhitespace)
            .compactMap { $0.first(where: \.isLetter) }
            .prefix(2)
        return words.isEmpty ? "•" : String(words).uppercased()
    }
}

extension CustomerType {
    var symbolName: String {
        switch self {
        case .person: "person.fill"
        case .company: "building.2.fill"
        }
    }

    var label: String {
        switch self {
        case .person: "Person"
        case .company: "Company"
        }
    }
}

// MARK: - Badges

/// The person/company badge that appears on every row and on the record header.
struct CustomerTypeBadge: View {
    let type: CustomerType

    var body: some View {
        Label(type.label, systemImage: type.symbolName)
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: .capsule)
            .accessibilityLabel(type.label)
    }
}

extension CustomerStatus {
    var label: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .pendingDeletion: "Pending deletion"
        }
    }

    var symbolName: String {
        switch self {
        case .active: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        case .pendingDeletion: "clock.badge.exclamationmark.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active: .green
        case .archived: .secondary
        case .pendingDeletion: DudoStyle.scarlet
        }
    }
}

/// The lifecycle badge.
///
/// `active` is the ordinary case and carries no badge in a listing — a directory where every
/// row shouts "Active" tells the reader nothing. It is shown explicitly on the record header,
/// where the question "what state is this in?" is actually being asked.
struct CustomerStatusBadge: View {
    let status: CustomerStatus
    var alwaysVisible = false

    var body: some View {
        if status != .active || alwaysVisible {
            Label(status.label, systemImage: status.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(status.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(status.tint.opacity(0.12), in: .capsule)
                .accessibilityLabel("Status: \(status.label)")
        }
    }
}

// MARK: - Detail rows

/// One field of a customer record: a label, a value, and an honest rendering of "not
/// recorded" when the field is present and null.
///
/// Optional fields are always present on the wire and null when unfilled, so there is exactly
/// one thing to show for an empty field and both Dudo clients show it the same way. A blank
/// space would leave the reader unsure whether the field exists.
struct CustomerFieldRow: View {
    let label: String
    let value: String?
    var systemImage: String?
    var isMonospaced = false
    var allowsMultipleLines = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DudoStyle.Space.row) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(isMonospaced ? .callout.monospaced() : .callout)
                        .textSelection(.enabled)
                        .lineLimit(allowsMultipleLines ? nil : 1)
                        .fixedSize(horizontal: false, vertical: allowsMultipleLines)
                } else {
                    Text("Not recorded")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Formatting

extension Date {
    /// Dates a person reads: "12 Mar 2026 at 14:30".
    var dudoLongForm: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    /// Dates a person skims in a list: "12 Mar 2026".
    var dudoShortForm: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}
