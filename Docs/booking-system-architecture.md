# Punch-In Booking System Architecture

## Overview
The booking system enables artists to reserve sessions with studios and engineers. It supports manual approvals and premium instant bookings while synchronizing studio, room, and engineer availability to prevent conflicts.

## Core Roles
- **Artist**: Initiates bookings. Can edit their pending requests and view confirmed/completed sessions.
- **Studio Owner**: Manages studios, rooms, operating hours, blackout dates, and handles manual booking approvals.
- **Engineer**: Maintains personal availability, blocks time, and chooses main studio each day. Premium engineers can enable instant booking and allow multi-studio requests.

## Firestore Data Model
```
profiles/{userId}
  accountType: "artist" | "engineer" | "studio"
  premium.isPremiumEngineer: bool
  premium.instantBookEnabled: bool
  premium.mainStudioId: string | null
  premium.allowOtherStudios: bool
  contact.phoneNumber/email: string
  ...existing profile fields

studios/{studioId}
  ownerId: string
  name, address, etc.
  operatingHours: map<weekday, [timeRange]>
  blackoutDates: [timestamp]
  instantRequestApproval: bool (manual backup)
  approvedEngineerIds: [string]

studios/{studioId}/rooms/{roomId}
  name: string
  description: string
  hourlyRate: number | null
  capacity: number | null
  amenities: [string]
  isDefault: bool

studioAvailability/{studioId}/entries/{availabilityId}
  type: "recurring" | "block" | "bookingHold" | "selfBooking"
  roomId: string | null
  weekday: number // 0-6 when recurring
  startTimeMinutes: number // minutes from midnight in studio timezone
  durationMinutes: number
  startDate: timestamp // for one-off blocks/holds
  endDate: timestamp | null
  sourceBookingId: string | null
  createdBy: string (uid)

engineerAvailability/{engineerId}/entries/{availabilityId}
  type: "recurring" | "block" | "selfBooking" | "bookingHold"
  weekday/startTimeMinutes/durationMinutes (for recurring)
  startDate/endDate (for one-off)
  sourceBookingId: string | null
  studioId: string | null
  notes: string

bookings/{bookingId}
  artistId: string
  studioId: string
  roomId: string
  engineerId: string
  status: "pending" | "confirmed" | "completed" | "cancelled" | "rescheduled"
  requestedStart: timestamp
  requestedEnd: timestamp
  confirmedStart: timestamp | null
  confirmedEnd: timestamp | null
  durationMinutes: number
  pricing: {
    hourlyRate: number
    total: number
    currency: string
  }
  instantBook: bool
  approval: {
    requiresStudio: bool
    requiresEngineer: bool
    resolvedBy: string | null
    resolvedAt: timestamp | null
  }
  conversationId: string | null // chat reference
  createdAt/updatedAt: timestamp
  notes: string

bookings/{bookingId}/timelineEvents/{eventId}
  type: "status_change" | "note" | "reminder" | "reschedule"
  message: string
  createdBy: string
  createdAt: timestamp

studioEngineerRelationships/{studioId}_{engineerId}
  studioId: string
  engineerId: string
  role: "member" | "pending"
  isPrimary: bool
  lastMainStudioAt: timestamp
```

## Backend Logic
1. **Booking Creation (Cloud Function)**
   - Receives booking request.
   - Validates studio operating hours, room availability, and engineer availability.
   - Confirms availability using aggregated availability documents.
   - Determines if instant booking is allowed (engineer premium + instant toggle + studio open + no conflicts).
   - Creates booking document with `pending` or `confirmed` status.
   - Writes booking holds to `studioAvailability` and `engineerAvailability` when confirmed/instant.
   - Triggers notifications to studio owner and engineer when approval is required.

2. **Booking Approval / Reschedule / Cancel (Cloud Functions)**
   - Transactionally update booking status.
   - Update availability entries (add or remove holds).
   - Append timeline events and send notifications.

3. **Availability Updates**
   - When studio or engineer creates recurring availability or blocks, Cloud Function recalculates aggregated availability snapshots to speed up lookups.
   - Self-booking by studio/engineer writes to bookings collection tagged as self-booking and blocks the time.

4. **Reminders & Expiry**
   - Scheduled Cloud Tasks send reminders 24h and 1h before confirmed sessions.
   - Automatically move past confirmed sessions to `completed`.

## Firestore Security Rules
- Artists can create bookings referencing `artistId == request.auth.uid`.
- Pending bookings: artist may update/cancel prior to approval.
- Studios/engineers can read bookings involving them and transition status (`pending -> confirmed/declined/rescheduled`, `confirmed -> cancelled/completed`).
- Premium engineer flags gate instant booking fields (only Firestore-backed custom claims or secure fields).
- Availability entries may only be written by entity owners.

## Client UI Overview
- **Studio Page**: Calendar view of rooms, booking button, list of pending requests.
- **Engineer Page**: Availability editor, toggle for instant booking, daily main studio selection, pending inbox.
- **Artist Flow**: Booking sheet selecting studio/engineer, date, start time, duration, room; conflict checks with inline feedback.
- **Inbox**: Studio/engineer to confirm/reschedule/decline requests with quick actions.
- **Booking Detail**: Timeline, notes, ability to chat, cancel/reschedule buttons.

## Testing Strategy
- Unit tests for availability filtering, instant booking decision, state transitions.
- Firestore emulator tests for security rules ensuring correct access control.
- Integration tests for Cloud Functions (request -> confirm -> cancellation).
- Manual QA scenarios:
  1. Instant booking success.
  2. Manual request approval by studio.
  3. Room conflict rejection.
  4. Engineer off-day block prevents scheduling.
  5. Premium toggle disables instant booking.
  6. Reschedule flow updates availability.
  7. Cancellation releases holds.
  8. Main studio switch updates booking eligibility.
