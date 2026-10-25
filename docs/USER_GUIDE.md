# Using Fleet Pocket

Fleet Pocket helps MCY coordinate authorised transport customers from a central workspace. This guide describes current behavior. Use fictional data for local acceptance testing and record the [known audit issues](AUDIT-2026-10-25.md).

## Choose the right customer

Use Customer fleet to select a transport company. All authorised fleets combines the companies your account can access. Vehicle groups and search narrow the fleet table. Customer portal uses its own customer selection.

Check the selected company before creating records. In the combined workspace, handover notes and Team & access currently default to the first customer; select one customer explicitly before using either. Seeing a company in a demo does not grant real customer access.

## Review the control tower

Review trips, delivery risks, missing PODs, overdue GPS signals and the attention list. Open a vehicle row with a click or Enter. The drawer shows registrations, trailer details, driver contact, load state, journey, last location, documents and recent activity.

The map shows last received positions. A marker is not proof that a vehicle is still there. Check its GPS timestamp and stale-signal label. A missing marker means there may be no confirmed coordinates. A map outage does not erase the fleet table.

Counts are snapshot indicators. Active vehicles currently counts registered vehicles, and active trips includes jobs at Created; these labels do not prove a truck is moving or a controller is on shift. A record-limit banner means counts and exports can be incomplete.

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

Known issue: if refresh fails or an estimate expires between refreshes, some views can retain an ETA and even show Within delivery window. Check source/validity and the sync banner; do not rely on that label as confirmation. Refresh and review a current estimate before communicating it.

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

Until audit A02 is fixed, do not edit the preview or interval while approval is saving. If anything changes, close the dialog, regenerate and approve again. This is a temporary testing precaution, not a substitute for the required fix. Saved updates can remain marked approved after their due time; check the displayed next time manually. There are no automatic reminders or automatic sends.

## Handle alerts and handovers

Incidents lists operational alerts and allows acknowledgement. Acknowledged means a controller has seen it; it does not mean the cause is resolved. Resolution, incident ownership and reopening are unfinished, and a persistent condition can create a new alert after acknowledgement.

Before handover, select a single customer, check outstanding trips/PODs, stale readings and exceptions, then record concise actions, responsible people and deadlines. Notes are audit entries; there is no formal incoming-controller sign-off or structured shift roster.

## Reports and customer access

Reports summarise the current available records. Delivery forecasts within window describes forecasts, not completed on-time deliveries. Unknown forecasts are shown separately. Exports follow the selected customer scope and the current record cap; they are not complete historical SLA evidence.

Customer administrators can create jobs and upload documents but cannot dispatch, verify documents or approve estimates. Team & access manages customer roles for existing accounts. It does not create identities or send invitations. Only MCY administrators and customer administrators can manage those customer memberships; controllers cannot grant access through this screen.

## Sync, shortcuts and help

The authenticated workspace refreshes roughly every 15 seconds while visible. Check the last-sync time and refresh-error banner. Use Refresh now when needed. A committed job is still saved if the subsequent display refresh fails; do not create a different submission to compensate.

Ctrl/Cmd K focuses fleet search, Enter opens a focused vehicle row, and Escape closes details/dialogs. Full keyboard and assistive-technology acceptance is still outstanding. Report issues using the [testing guide](TESTING.md), with fictional references and redacted screenshots.
