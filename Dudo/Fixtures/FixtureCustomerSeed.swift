import Foundation

// MARK: - Synthetic seed data
//
// EVERY RECORD BELOW IS INVENTED. No name, company, address, email address or telephone
// number here belongs to a real person or a real business, and none may ever be replaced with
// one. Email addresses use the `example.com` / `example.net` / `example.org` domains, which
// are reserved by RFC 2606 for documentation and cannot be delivered to. Telephone numbers
// are made up.
//
// This exists so the Customer Directory can be looked at and used before any server exists.
// It is not a migration, not a seed script, and it never reaches storage.

enum FixtureCustomerSeed {

    /// The Businesses of the one fictional Organization this fixture represents.
    /// See `BusinessReference` — these labels are fixture-local, not a contracted shape.
    static let businesses: [BusinessReference] = [
        BusinessReference(id: "bzn_4Kd91Xr7QmTa", name: "Falcon Bay Trading W.L.L."),
        BusinessReference(id: "bzn_Rp82hVuY3sLc", name: "Falcon Bay Logistics"),
        BusinessReference(id: "bzn_Zt55mNwK7dGe", name: "Falcon Bay Marine Services")
    ]

    /// The principal the fixture attributes every record to. Opaque, as the contract requires.
    static let principalID = "prn_9Fq3TzVb2LmAyw"
    static let secondPrincipalID = "prn_Ck7WdS1nRt4Voz"

    static func records() -> [Customer] {
        let trading = businesses[0].id
        let logistics = businesses[1].id
        let marine = businesses[2].id

        return [
            make(
                id: "cus_2Hy8VbQm4RdTzk", business: trading,
                name: "Al Nahda Building Supplies", type: .company,
                email: "accounts@alnahda-supplies.example.com", phone: "+973 1745 2200",
                country: "BH", address: "Building 214, Road 3801\nBlock 338, Umm Al Hassam\nManama",
                notes: "Pays on 30-day terms. Purchase orders come from Reem in procurement.",
                daysAgoCreated: 412, daysAgoUpdated: 9
            ),
            make(
                id: "cus_5Kf1PzWn8LcRvq", business: trading,
                name: "Amina Darwish", type: .person,
                email: "amina.darwish@example.com", phone: "+973 3611 0482",
                country: "BH", address: "Flat 12, Al Reem Tower\nJuffair",
                notes: nil,
                daysAgoCreated: 300, daysAgoUpdated: 300
            ),
            make(
                id: "cus_7Mq4XcTv2NbHjs", business: marine,
                name: "Blue Horizon Marine Charter", type: .company,
                email: "bookings@bluehorizon-charter.example.net", phone: "+973 1782 6611",
                country: "BH", address: "Berth 14, Marina District\nManama",
                notes: "Seasonal — quiet June through August.",
                daysAgoCreated: 265, daysAgoUpdated: 41
            ),
            make(
                id: "cus_9Nw6ZdUb5PfKgm", business: logistics,
                name: "Cedar Line Freight Company", type: .company,
                email: "ops@cedarline-freight.example.com", phone: "+971 4 555 0143",
                country: "AE", address: "Warehouse 7, Jebel Ali Free Zone\nDubai",
                notes: "Customs paperwork must name the consignee exactly as registered.",
                daysAgoCreated: 520, daysAgoUpdated: 3
            ),
            make(
                id: "cus_1Bd3RfYn7VtQlp", business: trading,
                name: "Daniela Ferreira", type: .person,
                email: "d.ferreira@example.org", phone: nil,
                country: "PT", address: nil,
                notes: "Prefers email. Timezone is two hours behind.",
                daysAgoCreated: 190, daysAgoUpdated: 190
            ),
            make(
                id: "cus_3Cf5TgZp9WuSnr", business: logistics,
                name: "Eastgate Warehousing Ltd", type: .company,
                email: nil, phone: "+44 20 7946 0812",
                country: "GB", address: "Unit 4, Eastgate Industrial Park\nLeeds LS9 8AA",
                notes: nil,
                daysAgoCreated: 610, daysAgoUpdated: 128
            ),
            make(
                id: "cus_6Dh7UjAq1XvTos", business: trading,
                name: "Fatima Al Bastaki", type: .person,
                email: "fatima.b@example.com", phone: "+973 3900 1177",
                country: "BH", address: "Villa 8, Road 1207\nBlock 712, Riffa",
                notes: nil,
                daysAgoCreated: 88, daysAgoUpdated: 12
            ),
            make(
                id: "cus_8Ej9VkBr3YwUpt", business: marine,
                name: "Gulf Anchor Engineering", type: .company,
                email: "info@gulfanchor-eng.example.com", phone: "+973 1799 4030",
                country: "BH", address: "Plot 42, Hidd Industrial Area",
                notes: "Site visits need 48 hours' notice and a gate pass.",
                daysAgoCreated: 470, daysAgoUpdated: 22
            ),
            make(
                id: "cus_0Fk1WlCs5ZxVqu", business: trading,
                name: "Hassan Karimi", type: .person,
                email: "hassan.karimi@example.net", phone: "+973 3455 7788",
                country: nil, address: nil,
                notes: nil,
                daysAgoCreated: 45, daysAgoUpdated: 45
            ),
            make(
                id: "cus_2Gl3XmDt7AyWrv", business: logistics,
                name: "Indigo Paper & Packaging", type: .company,
                email: "purchasing@indigopaper.example.com", phone: "+91 22 4000 1188",
                country: "IN", address: "Plot 19, MIDC Andheri East\nMumbai 400093",
                notes: "Quotes in USD. Lead time six weeks.",
                daysAgoCreated: 355, daysAgoUpdated: 60
            ),
            make(
                id: "cus_4Hm5YnEu9BzXsw", business: trading,
                name: "Jasmine Okonkwo", type: .person,
                email: "j.okonkwo@example.com", phone: "+44 7700 900412",
                country: "GB", address: "22 Bramley Court\nManchester M4 6EE",
                notes: "Introduced by Cedar Line Freight.",
                daysAgoCreated: 150, daysAgoUpdated: 30
            ),
            make(
                id: "cus_6Jn7ZoFv1CaYtx", business: marine,
                name: "Khalifa Marine Fuels", type: .company,
                email: "dispatch@khalifafuels.example.com", phone: "+973 1766 3021",
                country: "BH", address: "Fuel Terminal 2, Mina Salman\nManama",
                notes: nil,
                daysAgoCreated: 700, daysAgoUpdated: 210
            ),
            make(
                id: "cus_8Kp9ApGw3DbZuy", business: trading,
                name: "Lina Haddad", type: .person,
                email: "lina.haddad@example.org", phone: "+961 3 998 442",
                country: "LB", address: nil,
                notes: "Invoices must be addressed to her consultancy, not to her personally.",
                daysAgoCreated: 210, daysAgoUpdated: 15
            ),
            make(
                id: "cus_0Lq1BqHx5EcAvz", business: logistics,
                name: "Meridian Cold Chain GmbH", type: .company,
                email: "kontakt@meridian-coldchain.example.com", phone: "+49 40 300 1122",
                country: "DE", address: "Hafenstraße 118\n20359 Hamburg",
                notes: "Temperature logs required with every delivery note.",
                daysAgoCreated: 480, daysAgoUpdated: 5
            ),
            make(
                id: "cus_2Mr3CrIy7FdBwa", business: trading,
                name: "Noor Al Sayed", type: .person,
                email: "noor.alsayed@example.com", phone: "+973 3277 6600",
                country: "BH", address: "Apartment 903, Seef Heights\nSeef District",
                notes: nil,
                daysAgoCreated: 33, daysAgoUpdated: 33
            ),
            make(
                id: "cus_4Ns5DsJz9GeCxb", business: marine,
                name: "Orchid Bay Hotel Group", type: .company,
                email: "procurement@orchidbayhotels.example.com", phone: "+973 1712 8899",
                country: "BH", address: "Orchid Bay Resort, Zallaq Beach Road",
                notes: "Three properties. Bill each one separately.",
                daysAgoCreated: 390, daysAgoUpdated: 18
            ),
            make(
                id: "cus_6Pt7EtKa1HfDyc", business: trading,
                name: "Priya Raghunathan", type: .person,
                email: "priya.r@example.net", phone: nil,
                country: "IN", address: nil,
                notes: nil,
                daysAgoCreated: 120, daysAgoUpdated: 120
            ),
            make(
                id: "cus_8Qv9FuLb3JgEzd", business: logistics,
                name: "Quayside Customs Brokers", type: .company,
                email: "clearances@quayside-brokers.example.com", phone: "+973 1740 5566",
                country: "BH", address: "Office 305, Customs Plaza\nMina Salman",
                notes: nil,
                daysAgoCreated: 560, daysAgoUpdated: 75
            ),
            make(
                id: "cus_0Rw1GvMc5KhFae", business: trading,
                name: "Rashid Trading Establishment", type: .company,
                email: "rashid@rashid-trading.example.com", phone: "+966 11 400 2255",
                country: "SA", address: "Al Olaya Street, Building 44\nRiyadh 12211",
                notes: "Registered for VAT in Saudi Arabia.",
                daysAgoCreated: 640, daysAgoUpdated: 96
            ),
            make(
                id: "cus_2Sx3HwNd7LiGbf", business: trading,
                name: "Sofia Marchetti", type: .person,
                email: "s.marchetti@example.com", phone: "+39 06 8899 4410",
                country: "IT", address: "Via dei Coronari 88\n00186 Roma",
                notes: nil,
                daysAgoCreated: 275, daysAgoUpdated: 275
            ),

            make(
                id: "cus_1Ab2CdEf3GhIjk", business: logistics,
                name: "Aurora Tech Consulting", type: .company,
                email: "contracts@auroratech.example.com", phone: "+971 2 666 0190",
                country: "AE", address: "Level 11, Capital Gate\nAbu Dhabi",
                notes: nil,
                daysAgoCreated: 240, daysAgoUpdated: 27
            ),
            make(
                id: "cus_3Bc4DeFg5HiJkl", business: trading,
                name: "Bassam Al Muharraqi", type: .person,
                email: "bassam.m@example.com", phone: "+973 3922 4415",
                country: "BH", address: "House 55, Road 909\nMuharraq",
                notes: "Cash on collection.",
                daysAgoCreated: 175, daysAgoUpdated: 62
            ),
            make(
                id: "cus_5Cd6EfGh7IjKlm", business: marine,
                name: "Coral Reef Diving School", type: .company,
                email: "dive@coralreefschool.example.net", phone: "+973 1736 0808",
                country: "BH", address: "Unit 3, Marina Promenade",
                notes: "Invoices monthly, in arrears.",
                daysAgoCreated: 320, daysAgoUpdated: 11
            ),
            make(
                id: "cus_7De8FgHi9JkLmn", business: logistics,
                name: "Elena Novak", type: .person,
                email: "elena.novak@example.org", phone: "+420 222 314 088",
                country: "CZ", address: nil,
                notes: nil,
                daysAgoCreated: 95, daysAgoUpdated: 95
            ),
            make(
                id: "cus_9Ef0GhIj1KlMno", business: trading,
                name: "Falcon Ridge Security Services", type: .company,
                email: "ops@falconridge-security.example.com", phone: "+973 1755 9090",
                country: "BH", address: "Office 12, Seef Business Centre",
                notes: "Guards rotate quarterly; contact list changes with them.",
                daysAgoCreated: 430, daysAgoUpdated: 48
            ),
            make(
                id: "cus_1Fg2HiJk3LmNop", business: marine,
                name: "Grace Mwangi", type: .person,
                email: "grace.mwangi@example.com", phone: nil,
                country: "KE", address: "PO Box 4471\nMombasa",
                notes: nil,
                daysAgoCreated: 66, daysAgoUpdated: 66
            ),
            make(
                id: "cus_3Gh4IjKl5MnOpq", business: logistics,
                name: "Harborline Shipping Agency", type: .company,
                email: "agency@harborline.example.com", phone: "+968 24 700 331",
                country: "OM", address: "Port Sultan Qaboos, Gate 2\nMuttrah",
                notes: nil,
                daysAgoCreated: 385, daysAgoUpdated: 73
            ),
            make(
                id: "cus_5Hi6JkLm7NoPqr", business: trading,
                name: "Ibrahim Al Dosari", type: .person,
                email: "i.aldosari@example.net", phone: "+966 50 220 4471",
                country: "SA", address: nil,
                notes: "Speaks to Yousef only.",
                daysAgoCreated: 145, daysAgoUpdated: 20
            ),
            make(
                id: "cus_7Ij8KlMn9OpQrs", business: marine,
                name: "Juniper Fit Studios", type: .company,
                email: "hello@juniperfit.example.com", phone: "+973 1730 4422",
                country: "BH", address: "Ground floor, Amwaj Marina Walk",
                notes: nil,
                daysAgoCreated: 210, daysAgoUpdated: 210
            ),
            make(
                id: "cus_9Jk0LmNo1PqRst", business: trading,
                name: "Karim Boulos", type: .person,
                email: "karim.boulos@example.org", phone: "+20 2 2735 1180",
                country: "EG", address: "18 Sharia El Nil\nCairo",
                notes: nil,
                daysAgoCreated: 58, daysAgoUpdated: 58
            ),

            // --- archived ---------------------------------------------------------------
            // Withdrawn from active use and retained INDEFINITELY. Archive is not deletion
            // and starts no countdown: nothing in the platform will ever remove these on a
            // timer. They stay readable by identifier and are absent from the default listing.
            make(
                id: "cus_4Ty5IxOe9MjHcg", business: trading,
                name: "Tamarind Stationers", type: .company,
                email: "sales@tamarindstationers.example.com", phone: "+973 1723 4141",
                country: "BH", address: "Shop 12, Adliya Souq",
                notes: "Closed the Adliya branch. Kept in case they reopen.",
                status: .archived,
                daysAgoCreated: 820, daysAgoUpdated: 240
            ),
            make(
                id: "cus_6Uz7JyPf1NkIdh", business: logistics,
                name: "Umar Chaudhry", type: .person,
                email: "umar.chaudhry@example.org", phone: "+92 21 3456 7890",
                country: "PK", address: nil,
                notes: nil,
                status: .archived,
                daysAgoCreated: 505, daysAgoUpdated: 300
            ),
            make(
                id: "cus_8Va9KzQg3PlJei", business: marine,
                name: "Vela Yacht Provisioning", type: .company,
                email: nil, phone: "+973 3800 2244",
                country: "BH", address: "Dock 3, Marina District",
                notes: "Supplier changed hands. Reassess before reactivating.",
                status: .archived,
                daysAgoCreated: 445, daysAgoUpdated: 130
            ),
            make(
                id: "cus_0Wb1LaRh5QmKfj", business: trading,
                name: "Westford Office Interiors", type: .company,
                email: "hello@westford-interiors.example.com", phone: "+44 161 496 0177",
                country: "GB", address: "Westford House, 3 Peel Street\nManchester M2 1AA",
                notes: nil,
                status: .archived,
                daysAgoCreated: 690, daysAgoUpdated: 355
            )
        ]
    }

    // MARK: - Construction

    private static func make(
        id: String,
        business: String,
        name: String,
        type: CustomerType,
        email: String?,
        phone: String?,
        country: String?,
        address: String?,
        notes: String?,
        status: CustomerStatus = .active,
        daysAgoCreated: Int,
        daysAgoUpdated: Int
    ) -> Customer {
        Customer(
            customerID: id,
            businessID: business,
            displayName: name,
            customerType: type,
            email: email,
            phone: phone,
            country: country,
            address: address,
            notes: notes,
            status: status,
            // Null in every state except `pending_deletion`, which nothing in this slice can
            // reach — DeleteCustomer is contracted and deliberately not built.
            deletionScheduledAt: nil,
            createdAt: daysAgo(daysAgoCreated),
            createdByPrincipalID: principalID,
            updatedAt: daysAgo(daysAgoUpdated),
            updatedByPrincipalID: daysAgoUpdated == daysAgoCreated ? principalID : secondPrincipalID
        )
    }

    private static func daysAgo(_ days: Int) -> Date {
        // A fixed hour of the day keeps the seed stable within a session without pinning it
        // to a date that will look stale next month.
        Date(timeIntervalSinceNow: -Double(days) * 86_400 - 3_600 * 7)
    }
}
