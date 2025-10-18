import Foundation

enum MusicGenre: String, CaseIterable, Codable, Identifiable {
    case hipHop = "hip_hop"
    case rnb = "rnb"
    case pop = "pop"
    case rock = "rock"
    case alternative = "alternative"
    case electronic = "electronic"
    case house = "house"
    case techno = "techno"
    case dance = "dance"
    case country = "country"
    case folk = "folk"
    case jazz = "jazz"
    case blues = "blues"
    case soul = "soul"
    case gospel = "gospel"
    case latin = "latin"
    case afrobeat = "afrobeat"
    case reggae = "reggae"
    case dancehall = "dancehall"
    case metal = "metal"
    case punk = "punk"
    case classical = "classical"
    case soundtrack = "soundtrack"
    case loFi = "lo_fi"
    case spokenWord = "spoken_word"
    case experimental = "experimental"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hipHop:
            return "Hip-Hop"
        case .rnb:
            return "R&B"
        case .pop:
            return "Pop"
        case .rock:
            return "Rock"
        case .alternative:
            return "Alternative"
        case .electronic:
            return "Electronic"
        case .house:
            return "House"
        case .techno:
            return "Techno"
        case .dance:
            return "Dance"
        case .country:
            return "Country"
        case .folk:
            return "Folk"
        case .jazz:
            return "Jazz"
        case .blues:
            return "Blues"
        case .soul:
            return "Soul"
        case .gospel:
            return "Gospel"
        case .latin:
            return "Latin"
        case .afrobeat:
            return "Afrobeat"
        case .reggae:
            return "Reggae"
        case .dancehall:
            return "Dancehall"
        case .metal:
            return "Metal"
        case .punk:
            return "Punk"
        case .classical:
            return "Classical"
        case .soundtrack:
            return "Soundtrack"
        case .loFi:
            return "Lo-Fi"
        case .spokenWord:
            return "Spoken Word"
        case .experimental:
            return "Experimental"
        }
    }
}

enum USState: String, CaseIterable, Codable, Identifiable {
    case alabama = "AL"
    case alaska = "AK"
    case arizona = "AZ"
    case arkansas = "AR"
    case california = "CA"
    case colorado = "CO"
    case connecticut = "CT"
    case delaware = "DE"
    case districtOfColumbia = "DC"
    case florida = "FL"
    case georgia = "GA"
    case hawaii = "HI"
    case idaho = "ID"
    case illinois = "IL"
    case indiana = "IN"
    case iowa = "IA"
    case kansas = "KS"
    case kentucky = "KY"
    case louisiana = "LA"
    case maine = "ME"
    case maryland = "MD"
    case massachusetts = "MA"
    case michigan = "MI"
    case minnesota = "MN"
    case mississippi = "MS"
    case missouri = "MO"
    case montana = "MT"
    case nebraska = "NE"
    case nevada = "NV"
    case newHampshire = "NH"
    case newJersey = "NJ"
    case newMexico = "NM"
    case newYork = "NY"
    case northCarolina = "NC"
    case northDakota = "ND"
    case ohio = "OH"
    case oklahoma = "OK"
    case oregon = "OR"
    case pennsylvania = "PA"
    case rhodeIsland = "RI"
    case southCarolina = "SC"
    case southDakota = "SD"
    case tennessee = "TN"
    case texas = "TX"
    case utah = "UT"
    case vermont = "VT"
    case virginia = "VA"
    case washington = "WA"
    case westVirginia = "WV"
    case wisconsin = "WI"
    case wyoming = "WY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alabama: return "Alabama"
        case .alaska: return "Alaska"
        case .arizona: return "Arizona"
        case .arkansas: return "Arkansas"
        case .california: return "California"
        case .colorado: return "Colorado"
        case .connecticut: return "Connecticut"
        case .delaware: return "Delaware"
        case .districtOfColumbia: return "District of Columbia"
        case .florida: return "Florida"
        case .georgia: return "Georgia"
        case .hawaii: return "Hawaii"
        case .idaho: return "Idaho"
        case .illinois: return "Illinois"
        case .indiana: return "Indiana"
        case .iowa: return "Iowa"
        case .kansas: return "Kansas"
        case .kentucky: return "Kentucky"
        case .louisiana: return "Louisiana"
        case .maine: return "Maine"
        case .maryland: return "Maryland"
        case .massachusetts: return "Massachusetts"
        case .michigan: return "Michigan"
        case .minnesota: return "Minnesota"
        case .mississippi: return "Mississippi"
        case .missouri: return "Missouri"
        case .montana: return "Montana"
        case .nebraska: return "Nebraska"
        case .nevada: return "Nevada"
        case .newHampshire: return "New Hampshire"
        case .newJersey: return "New Jersey"
        case .newMexico: return "New Mexico"
        case .newYork: return "New York"
        case .northCarolina: return "North Carolina"
        case .northDakota: return "North Dakota"
        case .ohio: return "Ohio"
        case .oklahoma: return "Oklahoma"
        case .oregon: return "Oregon"
        case .pennsylvania: return "Pennsylvania"
        case .rhodeIsland: return "Rhode Island"
        case .southCarolina: return "South Carolina"
        case .southDakota: return "South Dakota"
        case .tennessee: return "Tennessee"
        case .texas: return "Texas"
        case .utah: return "Utah"
        case .vermont: return "Vermont"
        case .virginia: return "Virginia"
        case .washington: return "Washington"
        case .westVirginia: return "West Virginia"
        case .wisconsin: return "Wisconsin"
        case .wyoming: return "Wyoming"
        }
    }
}

enum RadioRegion: Equatable, Identifiable, Hashable {
    case nationwide
    case state(USState)

    var id: String {
        switch self {
        case .nationwide:
            return "nationwide"
        case let .state(state):
            return "state_\(state.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .nationwide:
            return "Nationwide"
        case let .state(state):
            return state.displayName
        }
    }

    var state: USState? {
        if case let .state(state) = self {
            return state
        }
        return nil
    }
}

struct RadioFeedFilter: Equatable {
    var genre: MusicGenre?
    var region: RadioRegion

    init(genre: MusicGenre? = nil, region: RadioRegion = .nationwide) {
        self.genre = genre
        self.region = region
    }
}
