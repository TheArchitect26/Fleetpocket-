# Using Fleet Pocket

Fleet Pocket helps MCY coordinate authorised transport customers from a central workspace. This guide describes current behavior. Use fictional data for local acceptance testing and record the [known audit issues](AUDIT-2026-10-25.md).

Current approval, expiry, incident and complete-record behavior is described in the [operational remediation](THIRD-REMEDIATION.md).

## Choose the right customer

Use Customer fleet to select a transport company. All authorised fleets combines the companies your account can access. Vehicle groups and search narrow the fleet table. Customer portal uses its own customer selection.

Check the selected company before creating records. Handover notes, Team & access and operational summaries require one explicitly selected customer; they cannot silently use the first customer in a combined workspace. Seeing a company in a demo does not grant real customer access.

## Review the control tower

Review trips, delivery risks, missing PODs, overdue GPS signals and the attention list. Open a vehicle row with a click or Enter. The drawer shows registrations, trailer details, driver contact, load state, journey, last location, documents and recent activity.

The map shows last received positions. A marker is not proof that a vehicle is still there. Check its GPS timestamp and stale-signal label. A missing marker means there may be no confirmed coordinates. A map outage does not erase the fleet table.

Counts are snapshot indicators. Registered vehicles and open work do not prove movement or attendance. A record-limit banner means the overview window is bounded: use All records for server-side pagination/search and the authenticated CSV for the complete authorised job scope.

## Create and dispatch a job

Select Create job, choose the correct vehicle and enter collection/delivery codes and customer names, cargo, delivery time and both stops' coordinates. The delivery time field uses your browser timezone; operational displays use SAST. Confirm coordinates with the customer; address lookup is not implemented.

The lifecycle is:

Created → Assigned → Accepted → En Route to Loading → At Loading → Loaded → In Transit → At Delivery → Delivered → POD Received → Closed.

A controller advances one stage at a time. Accepted is currently recorded by the controller; there is no driver acceptance application. Assignment records the acting controller; there is no controller-assignment roster or drag-and-drop dispatch planner.

Flag an exception with a reason, then resolve it with a note to resume the interrupted stage. Loaded jobs cannot be cancelled directly. There is no dedicated cargo-recovery, reassignment or route-editing workflow; escalate these cases to the supervisor rather than inventing a status.

Physical delivery empties the vehicle. Completing an older delivery's POD and closure must not empty a newer load. Closed and Cancelled jobs are terminal.

## Interpret and review ETAs

Loading ETA estimates arrival at collection. Delivery ETA estimates arrival at the delivery stop. Loading/service time and full multi-stop final-delivery forecasting are not modelled.

Controllers can review calculated estimates in vehicle details. Customer users receive an explicitly reviewed version, with its original GPS source and target stop, while it remains valid. New calculations do not silently replace that reviewed version. Route/stop changes, expiry or a material arrival difference withdraw publication.

Current defaults allow a reviewed estimate for at most 15 minutes from review and 30 minutes from its GPS source. A difference greater than 15 minutes from the reviewed arrival withdraws it. These thresholds require MCY acceptance before a pilot; detailed rules are in [the publication policy](SECOND-REMEDIATION.md).

Cached ETA values are withheld when their validity expires even if refresh fails. Unknown arrival remains distinct from within-window forecasts. Check the source and sync banner, then refresh and review current information before communicating it.

## Upload, verify and release delivery evidence

Documents & PODs accepts PDF, JPEG and PNG up to 10 MB. Choose the correct vehicle and, for POD, its matching job. A POD for a different vehicle/job cannot satisfy closure. Other documents may be vehicle-linked; a dedicated driver-document upload workflow is still needed.

Upload and verification are separate steps. MCY staff verify the file, then can release PODs, delivery instructions and loading documents to customer users. Verification alone does not release them. Customer administrators can also see their own uploads; customer viewers cannot see unreleased files. Other document types cannot currently be released through this workflow.

Preview / download opens a short-lived private link. Never forward that link as permanent customer access. The files have type/size checks but no malware scanning yet. For a wrong or superseded file, contact the supervisor: replacement, quarantine and release-revocation controls are incomplete.

## Prepare a vehicle update

Open a vehicle with a job and choose Generate Update. The preview uses this MCY structure:

```text
L/CPT (Loading Customer) - D/DBN (Offloading Customer)

Transporter:
Fleet No:
Horse Reg:
Trailer Reg:
Trailer Reg:
Status: Loaded/Empty
Cargo:

ETA:

Location:
```

The actual route codes, customers and vehicle/job values replace these placeholders. Review the stop, source timestamp, cargo and location, including stale/simulated labels. Choose 30, 60, 120 or 180 minutes, or a custom interval from 5 to 1440 minutes, then approve the final text. Copy Update copies it; Share to WhatsApp opens WhatsApp for your final send. Neither action proves delivery.

Approval is tied to the exact text, interval, vehicle and job version. Editing or changing context disables sharing until that version is approved; a delayed response cannot approve a different preview. Approval expires after at most 15 minutes, or sooner when its ETA expires. Due badges compare the scheduled time with the clock. The monitor creates deduplicated update-due incidents, including missing first updates on live work; the external monitor schedule must be running. There are no automatic WhatsApp sends or external reminder-delivery receipts.

## Handle alerts and handovers

Incidents allows acknowledgement, Take ownership and resolution with a required note. Acknowledged means seen, not resolved. Source recovery resolves the condition; a later recurrence reopens the same incident with a higher occurrence. Controllers can resolve an observed condition as an accepted exception, with that fact still shown; a continuing condition does not undo the explicit decision. Legacy alerts without a condition identity can be reviewed and resolved manually.

Before handover, select a single customer, check outstanding trips/PODs, stale readings and exceptions, then record concise actions, responsible people and deadlines. Notes are audit entries; there is no formal incoming-controller sign-off or structured shift roster.

## Reports and customer access

Reports summarise the current available records. Delivery forecasts within window describes forecasts, not completed on-time deliveries. Unknown forecasts are shown separately. Authenticated exports include all jobs in the selected authorised scope in one database snapshot, including records beyond the overview cap. They are still snapshot reports, not historical SLA evidence. All records provides paginated access to vehicles, drivers, jobs, documents, updates, incidents, handovers and audit history according to your permissions; paged jobs/documents/incidents have the displayed action controls. Pages are live and can move with concurrent changes, so refresh to restart a review.

Customer administrators can create jobs and upload documents but cannot dispatch, verify documents or approve estimates. Team & access manages customer roles for existing accounts. It does not create identities or send invitations. Only MCY administrators and customer administrators can manage those customer memberships; controllers cannot grant access through this screen.

## Sync, shortcuts and help

The authenticated workspace refreshes roughly every 15 seconds while visible. Check the last-sync time and refresh-error banner. Use Refresh now when needed. A committed job is still saved if the subsequent display refresh fails; do not create a different submission to compensate.

Ctrl/Cmd K focuses fleet search, Enter opens a focused vehicle row, and Escape closes details/dialogs. Full keyboard and assistive-technology acceptance is still outstanding. Report issues using the [testing guide](TESTING.md), with fictional references and redacted screenshots.
