//
//  ScheduledMessages.swift
//  Monal
//
//  isaCloud: scheduled messages, phase 1 (1:1 chats, text). The server sends the message at the chosen time
//  (docs/analise-mensagem-agendada.md). This file has what the chat shows: the rows, the times and the two sheets.
//  The actions (schedule, list, cancel) are in ChatView and xmpp.m.
//

import SwiftUI

/// isaCloud: a message waiting on the server, as the chat lists it. `body` is nil when it was scheduled from another device.
struct ScheduledMessageRow: Identifiable, Equatable {
    let serverId: String
    let scheduledAt: Date
    let body: String?

    var id: String { serverId }
}

enum ScheduledMessages {
    /// the furthest time a message can be scheduled for (the server refuses more: not-acceptable)
    static let maxDelay: TimeInterval = 72 * 60 * 60
    /// the nearest time the date picker offers
    static let minDelay: TimeInterval = 60

    /// a row of the local copies (DataLayer, table isacloud_scheduled_message)
    static func row(fromLocalCopy dict: [AnyHashable: Any]) -> ScheduledMessageRow? {
        guard let serverId = dict["server_id"] as? String, let seconds = dict["scheduled_at"] as? NSNumber else {
            return nil
        }
        return ScheduledMessageRow(serverId: serverId, scheduledAt: Date(timeIntervalSince1970: seconds.doubleValue), body: dict["body"] as? String)
    }

    /// the time shown in the chat and in the list, in the format of the device
    static func timeText(_ date: Date) -> String {
        //isaCloud: up to 72 h ahead, so another day shows its date too
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.twoDigits).hour().minute())
    }
}

/// isaCloud: the messages still waiting in this chat; "Cancel sending" takes one of them back to the field
struct ScheduledMessagesSheet: View {
    let rows: [ScheduledMessageRow]
    let onCancel: (ScheduledMessageRow) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        if let body = row.body {
                            Text(body)
                                .lineLimit(4)
                        } else {
                            Text("Scheduled on another device")
                                .foregroundStyle(.secondary)
                        }
                        Text(ScheduledMessages.timeText(row.scheduledAt))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Cancel sending", role: .destructive) {
                            onCancel(row)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Scheduled messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// isaCloud: the date and time for "Choose date and time…": from one minute to 72 hours ahead
struct ScheduleDatePickerSheet: View {
    let onSchedule: (Date) -> Void
    private let range: ClosedRange<Date>
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(onSchedule: @escaping (Date) -> Void) {
        self.onSchedule = onSchedule
        let now = Date()
        range = now.addingTimeInterval(ScheduledMessages.minDelay)...now.addingTimeInterval(ScheduledMessages.maxDelay)
        _date = State(initialValue: now.addingTimeInterval(5 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date and time", selection: $date, in: range)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Choose date and time…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        onSchedule(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
