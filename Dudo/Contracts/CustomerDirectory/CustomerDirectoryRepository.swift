import Foundation

/// The eight Customer Directory Actions this slice implements, as the Apple client sees them.
///
/// ONE METHOD PER ACTION, named after the Action, taking the Action's input shape and
/// returning the Action's output shape. Nothing is merged, nothing is convenience-wrapped,
/// and no method exists here that does not correspond to a contracted Action — a client-local
/// "saveCustomer" that decides between create and update would be this client inventing an
/// operation the platform does not have.
///
/// TWO CONTRACTED ACTIONS ARE DELIBERATELY ABSENT: `DeleteCustomer` and
/// `RestoreDeletedCustomer`. They are fully contracted and are ruled out of scope for the MVP
/// (contract §11.1, `mvpImplementationScope`), because the platform confirmation mechanism a
/// `critical` Action requires does not exist. Their absence here is the reason no delete
/// control appears anywhere in the interface, and it is not an oversight to be repaired.
///
/// THERE IS NO NETWORK BEHIND THIS PROTOCOL TODAY. `FixtureCustomerDirectoryRepository` is
/// the only conformer, it holds records in memory, and it makes no request of any kind. When
/// Core is reachable, a second conformer is written and no view changes.
@MainActor
protocol CustomerDirectoryRepository: AnyObject {

    /// `customers.CreateCustomer` — the new customer starts `active`. Does not check for
    /// duplicates: two customers may legitimately share a name or an email address.
    func createCustomer(_ input: CreateCustomerInput) async throws -> Customer

    /// `customers.GetCustomer` — the full record, including address and notes.
    /// Archived and pending-deletion customers remain readable by identifier; they are only
    /// withheld from the default listing.
    func getCustomer(customerID: String) async throws -> Customer

    /// `customers.ListCustomers` — one page, in the contract's fixed order.
    func listCustomers(_ input: ListCustomersInput) async throws -> CustomerPage

    /// `customers.SearchCustomers` — display name, email and phone only. Never notes, never
    /// address. The caller does not choose the fields.
    func searchCustomers(_ input: SearchCustomersInput) async throws -> CustomerPage

    /// `customers.UpdateCustomer` — a partial update of an `active` customer.
    func updateCustomer(_ input: UpdateCustomerInput) async throws -> Customer

    /// `customers.ArchiveCustomer` — `active` → `archived`. This never deletes data and
    /// starts no clock; an archived customer is retained indefinitely.
    func archiveCustomer(customerID: String) async throws -> Customer

    /// `customers.RestoreCustomer` — `archived` → `active`. Refuses `pending_deletion`.
    func restoreCustomer(customerID: String) async throws -> Customer

    /// `customers.MoveCustomerToBusiness` — between Businesses of the same Organization.
    /// Allowed on an archived customer; refused on a pending-deletion one.
    func moveCustomerToBusiness(customerID: String, businessID: String) async throws -> Customer
}
