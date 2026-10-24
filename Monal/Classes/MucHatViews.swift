//
//  MucHatViews.swift
//  Monal
//
//  isaCloud: the hats of the occupants of a room, read from DataLayer, and the pills that show them in the participants list.
//

import SwiftUI

enum MucHatStore {
    static func hats(room: String, nick: String?, accountID: NSNumber) -> [MucHat] {
        guard let nick, let list = DataLayer.sharedInstance().getMucHats(forRoom: room, nick: nick, forAccountID: accountID) as? [[String: String]] else {
            return []
        }
        return list.map { MucHat(uri: $0["uri"] ?? "", title: $0["title"] ?? "") }
    }
}

/// one pill per hat, below the name of the participant
struct MucHatPills: View {
    let hats: [MucHat]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(hats, id: \.self) { hat in
                let color = MucHat.paletteColor(forTitle: hat.title)
                Text(verbatim: hat.title)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
            }
        }
    }
}

extension MucHat {
    static func paletteColor(forTitle title: String) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal, .pink]
        return palette[paletteIndex(forTitle: title)]
    }
}
