# Fleet Pocket

**Fleet operations, coordinated by Musa Connect Yield (MCY).**

Fleet Pocket gives MCY controllers one workspace to oversee the transport companies they are authorised to manage. It brings vehicles, drivers, delivery jobs, location updates, documents and customer communication together so controllers can see what needs attention and keep each delivery moving.

Each transport company has its own fleet and records. MCY staff can switch between authorised customers or work across their authorised fleets. Customer users see the records their company and role permit.

## What the app does

| Workspace | What you can do |
|---|---|
| Control tower | Review vehicles, trips, delivery risks, overdue location signals and missing delivery paperwork. Open a vehicle without leaving the fleet view. |
| Fleet and drivers | Register vehicles and drivers, organise vehicles into customer groups, and view registrations, trailers, contacts, load state and recent history. |
| Jobs and dispatch | Create a transport job and advance it from assignment through loading, delivery, proof of delivery and closure. Record and resolve a job exception. |
| Tracking and ETAs | View the last received GPS position and its timestamp. Calculate road-based arrival estimates to the active loading or delivery stop when a tracking connection is configured. Review an estimate before customer publication. |
| Vehicle updates | Generate the MCY WhatsApp template from the vehicle and job, review the text, approve it, and copy it or open WhatsApp for a manual send. View saved update history. |
| Documents and PODs | Upload private PDF or image documents, preview them, verify delivery evidence, and release eligible documents to customer users. A matching verified POD is required before the delivery paperwork stages can finish. |
| Incidents and handovers | Review operational alerts, acknowledge them, inspect job exceptions and record notes for the next controller. |
| Reports | Review the current fleet snapshot, delivery forecasts and controller workload, and export the selected workspace to CSV. |
| Operations summary | Request a short summary of alert counts. When AI is unavailable, use the clearly labelled rules summary and check the original records. |
| Customer portal | Let authorised customer users follow their fleet, see reviewed arrival estimates and access released delivery documents. Customer administrators can submit jobs and manage customer access for existing accounts. |

## A typical delivery

A customer administrator or MCY staff member creates a job with a vehicle, cargo, collection point, destination and delivery time. A controller assigns it and moves it through collection and loading. When tracking is connected, Fleet Pocket records confirmed GPS readings and calculates an arrival estimate for the active stop.

The controller reviews customer-facing estimates and vehicle updates, follows up exceptions, then records delivery. After the matching POD has been uploaded and verified, the job can move through POD Received to Closed. Eligible documents can be released separately to the customer.

## Who uses it

- **MCY administrators:** oversee authorised customer workspaces and access arrangements.
- **Fleet controllers:** coordinate vehicles, dispatch, customer updates, delivery evidence and shift notes.
- **Customer administrators:** submit jobs, upload documents and manage customer-role access for existing users in their company.
- **Customer viewers:** follow their authorised fleet and view reviewed estimates and released documents.

Access is assigned per company. A staff role does not automatically grant access to every customer. Account creation and invitations currently require an administrator outside the app.

## Understanding the information

A GPS position is the last received reading, not a continuously moving estimate of a vehicle's location. An ETA is an estimate tied to a source reading and a specific stop. An arrival at loading is not a forecast of final delivery. Customer publication requires controller review and has a limited validity period.

Reports currently describe the available workspace snapshot. They are not historical delivery-performance or contractual SLA reports. Saving or sharing an update does not prove that a WhatsApp message was delivered.

## Current availability

Fleet Pocket is available as a **controlled local testing candidate**. A fictional demonstration includes three transport companies and twelve vehicles. The authenticated test workspace exercises actual sign-in, company isolation, dispatch and private document handling with fictional accounts and local test services.

A hosted preview and live tracking connections have not been configured. Automatic WhatsApp sending and reminder delivery are not implemented. Fleet editing, complete incident management, large-record pagination and production operating controls remain unfinished. The [current status](docs/STATUS.md) and [latest audit](docs/AUDIT-2026-10-25.md) describe these limits, including known issues testers should record.

## Learn more

- [User guide](docs/USER_GUIDE.md): using the workspace and handling a delivery.
- [Administrator and operations guide](docs/OPERATIONS.md): access, shift routines and service failures.
- [Testing guide](docs/TESTING.md): how to open the demo or authenticated test environment, test accounts and acceptance steps.
- [What comes next](docs/ROADMAP.md): priorities and the conditions for a live pilot.
- [Documentation directory](docs/README.md): product, testing and technical reference material.
