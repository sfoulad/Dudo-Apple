import SwiftUI

/// One row of the directory.
///
/// It shows only what `customerSummary` carries. `address` and `notes` are absent from the
/// list projection by design — that exclusion is the reason `list` is a separate permission
/// from `read` — and no row may reconstruct, cache or infer them.
struct CustomerRowView: View {
    let summary: CustomerSummary
    let businessLabel: String?

    var body: some View {
        HStack(alignment: .top, spacing: DudoStyle.Space.row) {
            CustomerAvatar(name: summary.displayName)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    CustomerStatusBadge(status: summary.status)
                    Spacer(minLength: 0)
                }

                Text(contactLine)
                    .font(.subheadline)
                    .foregroundStyle(hasContactDetails ? .secondary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // The type badge sits on the third line rather than in the trailing corner so
                // that the name gets the full width of the row. A directory is read by name.
                HStack(spacing: 6) {
                    CustomerTypeBadge(type: summary.customerType)
                    if let businessLabel {
                        Text(businessLabel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var hasContactDetails: Bool {
        summary.email != nil || summary.phone != nil
    }

    /// Email and phone are the contact-lookup fields the list deliberately carries — "a
    /// contact directory whose list cannot show a phone number is not a directory".
    ///
    /// One of them is shown, not both: in a row this width, two truncated values read as one
    /// mangled value. Email is preferred where there is one, the phone number takes its place
    /// where there is not, and the record itself shows both in full.
    private var contactLine: String {
        summary.email ?? summary.phone ?? "No contact details"
    }

    private var accessibilityLabel: String {
        var parts = [summary.displayName, summary.customerType.label]
        if summary.status != .active { parts.append(summary.status.label) }
        parts.append(hasContactDetails ? contactLine : "No contact details")
        if let businessLabel { parts.append(businessLabel) }
        return parts.joined(separator: ", ")
    }
}

/// The shape of a row before its data arrives. Real metrics, no content — so the list does not
/// jump when the first page lands.
struct CustomerRowPlaceholder: View {
    let widthSeed: Int

    var body: some View {
        HStack(spacing: DudoStyle.Space.row) {
            Circle()
                .fill(.quaternary)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: nameWidth, height: 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: detailWidth, height: 11)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private var nameWidth: CGFloat { [140, 190, 165, 120, 205].map(CGFloat.init)[widthSeed % 5] }
    private var detailWidth: CGFloat { [200, 150, 230, 175, 140].map(CGFloat.init)[widthSeed % 5] }
}
