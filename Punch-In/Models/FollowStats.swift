import Foundation

struct FollowStats: Equatable {
    var followersCount: Int
    var followingCount: Int
    var isFollowing: Bool
    var isFollowedBy: Bool

    static let empty = FollowStats(
        followersCount: 0,
        followingCount: 0,
        isFollowing: false,
        isFollowedBy: false
    )
}
