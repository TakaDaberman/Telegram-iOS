import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TelegramStringFormatting
import ItemListUI
import PresentationDataUtils
import AccountContext
import PresentationDataUtils
import AppBundle
import GraphUI
import ContextUI
import ItemListPeerItem
import InviteLinksUI
import UndoUI
import ShareController
import ItemListPeerActionItem
import PremiumUI
import StoryContainerScreen
import TelegramNotices
import ComponentFlow
import BoostLevelIconComponent

private let initialBoostersDisplayedLimit: Int32 = 5
private let initialTransactionsDisplayedLimit: Int32 = 5

private final class ChannelStatsControllerArguments {
    let context: AccountContext
    let loadDetailedGraph: (StatsGraph, Int64) -> Signal<StatsGraph?, NoError>
    let openPostStats: (EnginePeer, StatsPostItem) -> Void
    let openStory: (EngineStoryItem, UIView) -> Void
    let contextAction: (MessageId, ASDisplayNode, ContextGesture?) -> Void
    let copyBoostLink: (String) -> Void
    let shareBoostLink: (String) -> Void
    let openBoost: (ChannelBoostersContext.State.Boost) -> Void
    let expandBoosters: () -> Void
    let openGifts: () -> Void
    let createPrepaidGiveaway: (PrepaidGiveaway) -> Void
    let updateGiftsSelected: (Bool) -> Void
    
    let requestWithdraw: () -> Void
    let openMonetizationIntro: () -> Void
    let openMonetizationInfo: () -> Void
    let openTransaction: (RevenueStatsTransactionsContext.State.Transaction) -> Void
    let expandTransactions: () -> Void
    let updateCpmEnabled: (Bool) -> Void
    let presentCpmLocked: () -> Void
    let dismissInput: () -> Void
    
    init(context: AccountContext, loadDetailedGraph: @escaping (StatsGraph, Int64) -> Signal<StatsGraph?, NoError>, openPostStats: @escaping (EnginePeer, StatsPostItem) -> Void, openStory: @escaping (EngineStoryItem, UIView) -> Void, contextAction: @escaping (MessageId, ASDisplayNode, ContextGesture?) -> Void, copyBoostLink: @escaping (String) -> Void, shareBoostLink: @escaping (String) -> Void, openBoost: @escaping (ChannelBoostersContext.State.Boost) -> Void, expandBoosters: @escaping () -> Void, openGifts: @escaping () -> Void, createPrepaidGiveaway: @escaping (PrepaidGiveaway) -> Void, updateGiftsSelected: @escaping (Bool) -> Void, requestWithdraw: @escaping () -> Void, openMonetizationIntro: @escaping () -> Void, openMonetizationInfo: @escaping () -> Void, openTransaction: @escaping (RevenueStatsTransactionsContext.State.Transaction) -> Void, expandTransactions: @escaping () -> Void, updateCpmEnabled: @escaping (Bool) -> Void, presentCpmLocked: @escaping () -> Void, dismissInput: @escaping () -> Void) {
        self.context = context
        self.loadDetailedGraph = loadDetailedGraph
        self.openPostStats = openPostStats
        self.openStory = openStory
        self.contextAction = contextAction
        self.copyBoostLink = copyBoostLink
        self.shareBoostLink = shareBoostLink
        self.openBoost = openBoost
        self.expandBoosters = expandBoosters
        self.openGifts = openGifts
        self.createPrepaidGiveaway = createPrepaidGiveaway
        self.updateGiftsSelected = updateGiftsSelected
        self.requestWithdraw = requestWithdraw
        self.openMonetizationIntro = openMonetizationIntro
        self.openMonetizationInfo = openMonetizationInfo
        self.openTransaction = openTransaction
        self.expandTransactions = expandTransactions
        self.updateCpmEnabled = updateCpmEnabled
        self.presentCpmLocked = presentCpmLocked
        self.dismissInput = dismissInput
    }
}

private enum StatsSection: Int32 {
    case overview
    case growth
    case followers
    case notifications
    case viewsByHour
    case viewsBySource
    case followersBySource
    case languages
    case postInteractions
    case instantPageInteractions
    case reactionsByEmotion
    case storyInteractions
    case storyReactionsByEmotion
    case recentPosts
  
    case boostLevel
    case boostOverview
    case boostPrepaid
    case boosters
    case boostLink
    case boostGifts
    
    case adsHeader
    case adsImpressions
    case adsRevenue
    case adsProceeds
    case adsBalance
    case adsTransactions
    case adsCpm
}

enum StatsPostItem: Equatable {
    static func == (lhs: StatsPostItem, rhs: StatsPostItem) -> Bool {
        switch lhs {
        case let .message(lhsMessage):
            if case let .message(rhsMessage) = rhs {
                return lhsMessage.id == rhsMessage.id
            } else {
                return false
            }
        case let .story(lhsPeer, lhsStory):
            if case let .story(rhsPeer, rhsStory) = rhs, lhsPeer == rhsPeer, lhsStory == rhsStory {
                return true
            } else {
                return false
            }
        }
    }
    
    case message(Message)
    case story(EnginePeer, EngineStoryItem)
    
    var isStory: Bool {
        if case .story = self {
            return true
        } else {
            return false
        }
    }
    
    var timestamp: Int32 {
        switch self {
        case let .message(message):
            return message.timestamp
        case let .story(_, story):
            return story.timestamp
        }
    }
}

private enum StatsEntry: ItemListNodeEntry {
    case overviewTitle(PresentationTheme, String, String)
    case overview(PresentationTheme, ChannelStats)
    
    case growthTitle(PresentationTheme, String)
    case growthGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case followersTitle(PresentationTheme, String)
    case followersGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
     
    case notificationsTitle(PresentationTheme, String)
    case notificationsGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case viewsByHourTitle(PresentationTheme, String)
    case viewsByHourGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
        
    case viewsBySourceTitle(PresentationTheme, String)
    case viewsBySourceGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case followersBySourceTitle(PresentationTheme, String)
    case followersBySourceGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case languagesTitle(PresentationTheme, String)
    case languagesGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case postInteractionsTitle(PresentationTheme, String)
    case postInteractionsGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)

    case reactionsByEmotionTitle(PresentationTheme, String)
    case reactionsByEmotionGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case storyInteractionsTitle(PresentationTheme, String)
    case storyInteractionsGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case storyReactionsByEmotionTitle(PresentationTheme, String)
    case storyReactionsByEmotionGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case instantPageInteractionsTitle(PresentationTheme, String)
    case instantPageInteractionsGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case postsTitle(PresentationTheme, String)
    case post(Int32, PresentationTheme, PresentationStrings, PresentationDateTimeFormat, Peer, StatsPostItem, ChannelStatsPostInteractions)

    case boostLevel(PresentationTheme, Int32, Int32, CGFloat)
    
    case boostOverviewTitle(PresentationTheme, String)
    case boostOverview(PresentationTheme, ChannelBoostStatus, Bool)
    
    case boostPrepaidTitle(PresentationTheme, String)
    case boostPrepaid(Int32, PresentationTheme, String, String, PrepaidGiveaway)
    case boostPrepaidInfo(PresentationTheme, String)
    
    case boostersTitle(PresentationTheme, String)
    case boostersPlaceholder(PresentationTheme, String)
    case boosterTabs(PresentationTheme, String, String, Bool)
    case booster(Int32, PresentationTheme, PresentationDateTimeFormat, ChannelBoostersContext.State.Boost)
    case boostersExpand(PresentationTheme, String)
    case boostersInfo(PresentationTheme, String)
    
    case boostLinkTitle(PresentationTheme, String)
    case boostLink(PresentationTheme, String)
    case boostLinkInfo(PresentationTheme, String)
    
    case boostGifts(PresentationTheme, String)
    case boostGiftsInfo(PresentationTheme, String)
    
    case adsHeader(PresentationTheme, String)
  
    case adsImpressionsTitle(PresentationTheme, String)
    case adsImpressionsGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType)
    
    case adsRevenueTitle(PresentationTheme, String)
    case adsRevenueGraph(PresentationTheme, PresentationStrings, PresentationDateTimeFormat, StatsGraph, ChartType, Double)
    
    case adsProceedsTitle(PresentationTheme, String)
    case adsProceedsOverview(PresentationTheme, RevenueStats, TelegramMediaFile?)

    case adsBalanceTitle(PresentationTheme, String)
    case adsBalance(PresentationTheme, RevenueStats, Bool, Bool, TelegramMediaFile?)
    case adsBalanceInfo(PresentationTheme, String)
    
    case adsTransactionsTitle(PresentationTheme, String)
    case adsTransaction(Int32, PresentationTheme, RevenueStatsTransactionsContext.State.Transaction)
    case adsTransactionsExpand(PresentationTheme, String)
    
    case adsCpmToggle(PresentationTheme, String, Int32, Bool?)
    case adsCpmInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .overviewTitle, .overview:
                return StatsSection.overview.rawValue
            case .growthTitle, .growthGraph:
                return StatsSection.growth.rawValue
            case .followersTitle, .followersGraph:
                return StatsSection.followers.rawValue
            case .notificationsTitle, .notificationsGraph:
                return StatsSection.notifications.rawValue
            case .viewsByHourTitle, .viewsByHourGraph:
                return StatsSection.viewsByHour.rawValue
            case .viewsBySourceTitle, .viewsBySourceGraph:
                return StatsSection.viewsBySource.rawValue
            case .followersBySourceTitle, .followersBySourceGraph:
                return StatsSection.followersBySource.rawValue
            case .languagesTitle, .languagesGraph:
                return StatsSection.languages.rawValue
            case .postInteractionsTitle, .postInteractionsGraph:
                return StatsSection.postInteractions.rawValue
            case .instantPageInteractionsTitle, .instantPageInteractionsGraph:
                return StatsSection.instantPageInteractions.rawValue
            case .reactionsByEmotionTitle, .reactionsByEmotionGraph:
                return StatsSection.reactionsByEmotion.rawValue
            case .storyInteractionsTitle, .storyInteractionsGraph:
                return StatsSection.storyInteractions.rawValue
            case .storyReactionsByEmotionTitle, .storyReactionsByEmotionGraph:
                return StatsSection.storyReactionsByEmotion.rawValue
            case .postsTitle, .post:
                return StatsSection.recentPosts.rawValue
            case .boostLevel:
                return StatsSection.boostLevel.rawValue
            case .boostOverviewTitle, .boostOverview:
                return StatsSection.boostOverview.rawValue
            case .boostPrepaidTitle, .boostPrepaid, .boostPrepaidInfo:
                return StatsSection.boostPrepaid.rawValue
            case .boostersTitle, .boostersPlaceholder, .boosterTabs, .booster, .boostersExpand, .boostersInfo:
                return StatsSection.boosters.rawValue
            case .boostLinkTitle, .boostLink, .boostLinkInfo:
                return StatsSection.boostLink.rawValue
            case .boostGifts, .boostGiftsInfo:
                return StatsSection.boostGifts.rawValue
            case .adsHeader:
                return StatsSection.adsHeader.rawValue
            case .adsImpressionsTitle, .adsImpressionsGraph:
                return StatsSection.adsImpressions.rawValue
            case .adsRevenueTitle, .adsRevenueGraph:
                return StatsSection.adsRevenue.rawValue
            case .adsProceedsTitle, .adsProceedsOverview:
                return StatsSection.adsProceeds.rawValue
            case .adsBalanceTitle, .adsBalance, .adsBalanceInfo:
                return StatsSection.adsBalance.rawValue
            case .adsTransactionsTitle, .adsTransaction, .adsTransactionsExpand:
                return StatsSection.adsTransactions.rawValue
            case .adsCpmToggle, .adsCpmInfo:
                return StatsSection.adsCpm.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .overviewTitle:
                return 0
            case .overview:
                return 1
            case .growthTitle:
                return 2
            case .growthGraph:
                return 3
            case .followersTitle:
                return 4
            case .followersGraph:
                return 5
            case .notificationsTitle:
                return 6
            case .notificationsGraph:
                return 7
            case .viewsByHourTitle:
                return 8
            case .viewsByHourGraph:
                return 9
            case .viewsBySourceTitle:
                return 10
            case .viewsBySourceGraph:
                return 11
            case .followersBySourceTitle:
                return 12
            case .followersBySourceGraph:
                return 13
            case .languagesTitle:
                return 14
            case .languagesGraph:
                return 15
            case .postInteractionsTitle:
                return 16
            case .postInteractionsGraph:
                return 17
            case .instantPageInteractionsTitle:
                return 18
            case .instantPageInteractionsGraph:
                return 19
            case .reactionsByEmotionTitle:
                return 20
            case .reactionsByEmotionGraph:
                return 21
            case .storyInteractionsTitle:
                return 22
            case .storyInteractionsGraph:
                return 23
            case .storyReactionsByEmotionTitle:
                return 24
            case .storyReactionsByEmotionGraph:
                return 25
            case .postsTitle:
                return 26
            case let .post(index, _, _, _, _, _, _):
                return 27 + index
            case .boostLevel:
                return 2000
            case .boostOverviewTitle:
                return 2001
            case .boostOverview:
                return 2002
            case .boostPrepaidTitle:
                return 2003
            case let .boostPrepaid(index, _, _, _, _):
                return 2004 + index
            case .boostPrepaidInfo:
                return 2100
            case .boostersTitle:
                return 2101
            case .boostersPlaceholder:
                return 2102
            case .boosterTabs:
                return 2103
            case let .booster(index, _, _, _):
                return 2104 + index
            case .boostersExpand:
                return 10000
            case .boostersInfo:
                return 10001
            case .boostLinkTitle:
                return 10002
            case .boostLink:
                return 10003
            case .boostLinkInfo:
                return 10004
            case .boostGifts:
                return 10005
            case .boostGiftsInfo:
                return 10006
            case .adsHeader:
                return 20000
            case .adsImpressionsTitle:
                return 20001
            case .adsImpressionsGraph:
                return 20002
            case .adsRevenueTitle:
                return 20003
            case .adsRevenueGraph:
                return 20004
            case .adsProceedsTitle:
                return 20005
            case .adsProceedsOverview:
                return 20006
            case .adsBalanceTitle:
                return 20007
            case .adsBalance:
                return 20008
            case .adsBalanceInfo:
                return 20009
            case .adsTransactionsTitle:
                return 20010
            case let .adsTransaction(index, _, _):
                return 20011 + index
            case .adsTransactionsExpand:
                return 30000
            case .adsCpmToggle:
                return 30001
            case .adsCpmInfo:
                return 30002
        }
    }
    
    static func ==(lhs: StatsEntry, rhs: StatsEntry) -> Bool {
        switch lhs {
            case let .overviewTitle(lhsTheme, lhsText, lhsDates):
                if case let .overviewTitle(rhsTheme, rhsText, rhsDates) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsDates == rhsDates {
                    return true
                } else {
                    return false
                }
            case let .overview(lhsTheme, lhsStats):
                if case let .overview(rhsTheme, rhsStats) = rhs, lhsTheme === rhsTheme, lhsStats == rhsStats {
                    return true
                } else {
                    return false
                }
            case let .growthTitle(lhsTheme, lhsText):
                if case let .growthTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .growthGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .growthGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .followersTitle(lhsTheme, lhsText):
                if case let .followersTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .followersGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .followersGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .notificationsTitle(lhsTheme, lhsText):
                  if case let .notificationsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                      return true
                  } else {
                      return false
                  }
            case let .notificationsGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .notificationsGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .viewsByHourTitle(lhsTheme, lhsText):
                if case let .viewsByHourTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .viewsByHourGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .viewsByHourGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .viewsBySourceTitle(lhsTheme, lhsText):
                if case let .viewsBySourceTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .viewsBySourceGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .viewsBySourceGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .followersBySourceTitle(lhsTheme, lhsText):
                if case let .followersBySourceTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .followersBySourceGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .followersBySourceGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .languagesTitle(lhsTheme, lhsText):
                if case let .languagesTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .languagesGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .languagesGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .postInteractionsTitle(lhsTheme, lhsText):
                if case let .postInteractionsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .postInteractionsGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .postInteractionsGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .postsTitle(lhsTheme, lhsText):
                if case let .postsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .instantPageInteractionsTitle(lhsTheme, lhsText):
                if case let .instantPageInteractionsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .instantPageInteractionsGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .instantPageInteractionsGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .reactionsByEmotionTitle(lhsTheme, lhsText):
                if case let .reactionsByEmotionTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .reactionsByEmotionGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .reactionsByEmotionGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .storyInteractionsTitle(lhsTheme, lhsText):
                if case let .storyInteractionsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .storyInteractionsGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .storyInteractionsGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .storyReactionsByEmotionTitle(lhsTheme, lhsText):
                if case let .storyReactionsByEmotionTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .storyReactionsByEmotionGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .storyReactionsByEmotionGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .post(lhsIndex, lhsTheme, lhsStrings, lhsDateTimeFormat, lhsPeer, lhsPost, lhsInteractions):
                if case let .post(rhsIndex, rhsTheme, rhsStrings, rhsDateTimeFormat, rhsPeer, rhsPost, rhsInteractions) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, arePeersEqual(lhsPeer, rhsPeer), lhsPost == rhsPost, lhsInteractions == rhsInteractions {
                    return true
                } else {
                    return false
                }
            case let .boostLevel(lhsTheme, lhsBoosts, lhsLevel, lhsPosition):
                if case let .boostLevel(rhsTheme, rhsBoosts, rhsLevel, rhsPosition) = rhs, lhsTheme === rhsTheme, lhsBoosts == rhsBoosts, lhsLevel == rhsLevel, lhsPosition == rhsPosition {
                    return true
                } else {
                    return false
                }
            case let .boostOverviewTitle(lhsTheme, lhsText):
                if case let .boostOverviewTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostOverview(lhsTheme, lhsStats, lhsIsGroup):
                if case let .boostOverview(rhsTheme, rhsStats, rhsIsGroup) = rhs, lhsTheme === rhsTheme, lhsStats == rhsStats, lhsIsGroup == rhsIsGroup {
                    return true
                } else {
                    return false
                }
            case let .boostPrepaidTitle(lhsTheme, lhsText):
                if case let .boostPrepaidTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostPrepaid(lhsIndex, lhsTheme, lhsTitle, lhsSubtitle, lhsPrepaidGiveaway):
                if case let .boostPrepaid(rhsIndex, rhsTheme, rhsTitle, rhsSubtitle, rhsPrepaidGiveaway) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsSubtitle == rhsSubtitle, lhsPrepaidGiveaway == rhsPrepaidGiveaway {
                    return true
                } else {
                    return false
                }
            case let .boostPrepaidInfo(lhsTheme, lhsText):
                if case let .boostPrepaidInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostersTitle(lhsTheme, lhsText):
                if case let .boostersTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostersPlaceholder(lhsTheme, lhsText):
                if case let .boostersPlaceholder(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boosterTabs(lhsTheme, lhsBoostText, lhsGiftText, lhsGiftSelected):
                if case let .boosterTabs(rhsTheme, rhsBoostText, rhsGiftText, rhsGiftSelected) = rhs, lhsTheme === rhsTheme, lhsBoostText == rhsBoostText, lhsGiftText == rhsGiftText, lhsGiftSelected == rhsGiftSelected {
                    return true
                } else {
                    return false
                }
            case let .booster(lhsIndex, lhsTheme, lhsDateTimeFormat, lhsBoost):
                if case let .booster(rhsIndex, rhsTheme, rhsDateTimeFormat, rhsBoost) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsDateTimeFormat == rhsDateTimeFormat, lhsBoost == rhsBoost {
                    return true
                } else {
                    return false
                }
            case let .boostersExpand(lhsTheme, lhsText):
                if case let .boostersExpand(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostersInfo(lhsTheme, lhsText):
                if case let .boostersInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostLinkTitle(lhsTheme, lhsText):
                if case let .boostLinkTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostLink(lhsTheme, lhsText):
                if case let .boostLink(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostLinkInfo(lhsTheme, lhsText):
                if case let .boostLinkInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostGifts(lhsTheme, lhsText):
                if case let .boostGifts(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .boostGiftsInfo(lhsTheme, lhsText):
                if case let .boostGiftsInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsHeader(lhsTheme, lhsText):
                if case let .adsHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsImpressionsTitle(lhsTheme, lhsText):
                if case let .adsImpressionsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsImpressionsGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType):
                if case let .adsImpressionsGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType {
                    return true
                } else {
                    return false
                }
            case let .adsRevenueTitle(lhsTheme, lhsText):
                if case let .adsRevenueTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsRevenueGraph(lhsTheme, lhsStrings, lhsDateTimeFormat, lhsGraph, lhsType, lhsRate):
                if case let .adsRevenueGraph(rhsTheme, rhsStrings, rhsDateTimeFormat, rhsGraph, rhsType, rhsRate) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsDateTimeFormat == rhsDateTimeFormat, lhsGraph == rhsGraph, lhsType == rhsType,  lhsRate == rhsRate {
                    return true
                } else {
                    return false
                }
            case let .adsProceedsTitle(lhsTheme, lhsText):
                if case let .adsProceedsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsProceedsOverview(lhsTheme, lhsStatus, lhsAnimatedEmoji):
                if case let .adsProceedsOverview(rhsTheme, rhsStatus, rhsAnimatedEmoji) = rhs, lhsTheme === rhsTheme, lhsStatus == rhsStatus, lhsAnimatedEmoji == rhsAnimatedEmoji {
                    return true
                } else {
                    return false
                }
            case let .adsBalanceTitle(lhsTheme, lhsText):
                if case let .adsBalanceTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsBalance(lhsTheme, lhsStats, lhsCanWithdraw, lhsIsEnabled, lhsAnimatedEmoji):
                if case let .adsBalance(rhsTheme, rhsStats, rhsCanWithdraw, rhsIsEnabled, rhsAnimatedEmoji) = rhs, lhsTheme === rhsTheme, lhsStats == rhsStats, lhsCanWithdraw == rhsCanWithdraw, lhsIsEnabled == rhsIsEnabled, lhsAnimatedEmoji == rhsAnimatedEmoji {
                    return true
                } else {
                    return false
                }
            case let .adsBalanceInfo(lhsTheme, lhsText):
                if case let .adsBalanceInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsTransactionsTitle(lhsTheme, lhsText):
                if case let .adsTransactionsTitle(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsTransaction(lhsIndex, lhsTheme, lhsTransaction):
                if case let .adsTransaction(rhsIndex, rhsTheme, rhsTransaction) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsTransaction == rhsTransaction {
                    return true
                } else {
                    return false
                }
            case let .adsTransactionsExpand(lhsTheme, lhsText):
                if case let .adsTransactionsExpand(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .adsCpmToggle(lhsTheme, lhsText, lhsMinLevel, lhsValue):
                if case let .adsCpmToggle(rhsTheme, rhsText, rhsMinLevel, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsMinLevel == rhsMinLevel, lhsValue == rhsValue {
                    return true
                } else {
                    return false
                }
            case let .adsCpmInfo(lhsTheme, lhsText):
                if case let .adsCpmInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: StatsEntry, rhs: StatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ChannelStatsControllerArguments
        switch self {
            case let .overviewTitle(_, text, dates):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, accessoryText: ItemListSectionHeaderAccessoryText(value: dates, color: .generic), sectionId: self.section)
            case let .growthTitle(_, text),
                 let .followersTitle(_, text),
                 let .notificationsTitle(_, text),
                 let .viewsByHourTitle(_, text),
                 let .viewsBySourceTitle(_, text),
                 let .followersBySourceTitle(_, text),
                 let .languagesTitle(_, text),
                 let .postInteractionsTitle(_, text),
                 let .instantPageInteractionsTitle(_, text),
                 let .reactionsByEmotionTitle(_, text),
                 let .storyInteractionsTitle(_, text),
                 let .storyReactionsByEmotionTitle(_, text),
                 let .postsTitle(_, text),
                 let .boostOverviewTitle(_, text),
                 let .boostPrepaidTitle(_, text),
                 let .boostersTitle(_, text),
                 let .boostLinkTitle(_, text),
                 let .adsImpressionsTitle(_, text),
                 let .adsRevenueTitle(_, text),
                 let .adsProceedsTitle(_, text),
                 let .adsBalanceTitle(_, text),
                 let .adsTransactionsTitle(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .boostPrepaidInfo(_, text),
                 let .boostersInfo(_, text),
                 let .boostLinkInfo(_, text),
                 let .boostGiftsInfo(_, text),
                 let .adsCpmInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section)
            case let .overview(_, stats):
                return StatsOverviewItem(context: arguments.context, presentationData: presentationData, isGroup: false, stats: stats, sectionId: self.section, style: .blocks)
            case let .growthGraph(_, _, _, graph, type),
                 let .followersGraph(_, _, _, graph, type),
                 let .notificationsGraph(_, _, _, graph, type),
                 let .viewsByHourGraph(_, _, _, graph, type),
                 let .viewsBySourceGraph(_, _, _, graph, type),
                 let .followersBySourceGraph(_, _, _, graph, type),
                 let .languagesGraph(_, _, _, graph, type),
                 let .reactionsByEmotionGraph(_, _, _, graph, type),
                 let .storyReactionsByEmotionGraph(_, _, _, graph, type),
                 let .adsImpressionsGraph(_, _, _, graph, type):
                return StatsGraphItem(presentationData: presentationData, graph: graph, type: type, sectionId: self.section, style: .blocks)
            case let .adsRevenueGraph(_, _, _, graph, type, rate):
                return StatsGraphItem(presentationData: presentationData, graph: graph, type: type, conversionRate: rate, sectionId: self.section, style: .blocks)
            case let .postInteractionsGraph(_, _, _, graph, type),
                 let .instantPageInteractionsGraph(_, _, _, graph, type),
                 let .storyInteractionsGraph(_, _, _, graph, type):
                return StatsGraphItem(presentationData: presentationData, graph: graph, type: type, getDetailsData: { date, completion in
                    let _ = arguments.loadDetailedGraph(graph, Int64(date.timeIntervalSince1970) * 1000).start(next: { graph in
                        if let graph = graph, case let .Loaded(_, data) = graph {
                            completion(data)
                        }
                    })
                }, sectionId: self.section, style: .blocks)
            case let .post(_, _, _, _, peer, post, interactions):
                return StatsMessageItem(context: arguments.context, presentationData: presentationData, peer: peer, item: post, views: interactions.views, reactions: interactions.reactions, forwards: interactions.forwards, sectionId: self.section, style: .blocks, action: {
                    arguments.openPostStats(EnginePeer(peer), post)
                }, openStory: { sourceView in
                    if case let .story(_, story) = post {
                        arguments.openStory(story, sourceView)
                    }
                }, contextAction: !post.isStory ? { node, gesture in
                    if case let .message(message) = post {
                        arguments.contextAction(message.id, node, gesture)
                    }
                } : nil)
            case let .boosterTabs(_, boostText, giftText, giftSelected):
                return BoostsTabsItem(theme: presentationData.theme, boostsText: boostText, giftsText: giftText, selectedTab: giftSelected ? .gifts : .boosts, sectionId: self.section, selectionUpdated: { tab in
                    arguments.updateGiftsSelected(tab == .gifts)
                })
            case let .booster(_, _, _, boost):
                let count = boost.multiplier
                let expiresValue = stringForDate(timestamp: boost.expires, strings: presentationData.strings)
                let expiresString: String
                
                let durationMonths = Int32(round(Float(boost.expires - boost.date) / (86400.0 * 30.0)))
                let durationString = presentationData.strings.Stats_Boosts_ShortMonth("\(durationMonths)").string
            
                let title: String
                let icon: GiftOptionItem.Icon
                var label: String?
                if boost.flags.contains(.isGiveaway) {
                    label = "🏆 \(presentationData.strings.Stats_Boosts_Giveaway)"
                } else if boost.flags.contains(.isGift) {
                    label = "🎁 \(presentationData.strings.Stats_Boosts_Gift)"
                }
            
                let color: GiftOptionItem.Icon.Color
                if durationMonths > 11 {
                    color = .red
                } else if durationMonths > 5 {
                    color = .blue
                } else {
                    color = .green
                }
            
                if boost.flags.contains(.isUnclaimed) {
                    title = presentationData.strings.Stats_Boosts_Unclaimed
                    icon = .image(color: color, name: "Premium/Unclaimed")
                    expiresString = "\(durationString) • \(expiresValue)"
                } else if let peer = boost.peer {
                    title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                    icon = .peer(peer)
                    if let _ = label {
                        expiresString = "\(durationString) • \(expiresValue)"
                    } else {
                        expiresString = presentationData.strings.Stats_Boosts_ExpiresOn(expiresValue).string
                    }
                } else {
                    if boost.flags.contains(.isUnclaimed) {
                        title = presentationData.strings.Stats_Boosts_Unclaimed
                        icon = .image(color: color, name: "Premium/Unclaimed")
                    } else if boost.flags.contains(.isGiveaway) {
                        title = presentationData.strings.Stats_Boosts_ToBeDistributed
                        icon = .image(color: color, name: "Premium/ToBeDistributed")
                    } else {
                        title = "Unknown"
                        icon = .image(color: color, name: "Premium/ToBeDistributed")
                    }
                    expiresString = "\(durationString) • \(expiresValue)"
                }
                return GiftOptionItem(presentationData: presentationData, context: arguments.context, icon: icon, title: title, titleFont: .bold, titleBadge: count > 1 ? "\(count)" : nil, subtitle: expiresString, label: label.flatMap { .semitransparent($0) }, sectionId: self.section, action: {
                    arguments.openBoost(boost)
                })
            case let .boostersExpand(theme, title):
                return ItemListPeerActionItem(presentationData: presentationData, icon: PresentationResourcesItemList.downArrowImage(theme), title: title, sectionId: self.section, editing: false, action: {
                    arguments.expandBoosters()
                })
            case let .boostLevel(_, count, level, position):
                let inactiveText = presentationData.strings.ChannelBoost_Level("\(level)").string
                let activeText = presentationData.strings.ChannelBoost_Level("\(level + 1)").string
                return BoostLevelHeaderItem(theme: presentationData.theme, count: count, position: position, activeText: activeText, inactiveText: inactiveText, sectionId: self.section)
            case let .boostOverview(_, stats, isGroup):
                return StatsOverviewItem(context: arguments.context, presentationData: presentationData, isGroup: isGroup, stats: stats, sectionId: self.section, style: .blocks)
            case let .boostLink(_, link):
                let invite: ExportedInvitation = .link(link: link, title: nil, isPermanent: false, requestApproval: false, isRevoked: false, adminId: PeerId(0), date: 0, startDate: nil, expireDate: nil, usageLimit: nil, count: nil, requestedCount: nil)
                return ItemListPermanentInviteLinkItem(context: arguments.context, presentationData: presentationData, invite: invite, count: 0, peers: [], displayButton: true, displayImporters: false, buttonColor: nil, sectionId: self.section, style: .blocks, copyAction: {
                    arguments.copyBoostLink(link)
                }, shareAction: {
                    arguments.shareBoostLink(link)
                }, contextAction: nil, viewAction: nil, tag: nil)
            case let .boostersPlaceholder(_, text):
                return ItemListPlaceholderItem(theme: presentationData.theme, text: text, sectionId: self.section, style: .blocks)
            case let .boostGifts(theme, title):
                return ItemListPeerActionItem(presentationData: presentationData, icon: PresentationResourcesItemList.addBoostsIcon(theme), title: title, sectionId: self.section, editing: false, action: {
                    arguments.openGifts()
                })
            case let .boostPrepaid(_, _, title, subtitle, prepaidGiveaway):
                let color: GiftOptionItem.Icon.Color
                switch prepaidGiveaway.months {
                case 3:
                    color = .green
                case 6:
                    color = .blue
                case 12:
                    color = .red
                default:
                    color = .blue
                }
                return GiftOptionItem(presentationData: presentationData, context: arguments.context, icon: .image(color: color, name: "Premium/Giveaway"), title: title, titleFont: .bold, titleBadge: "\(prepaidGiveaway.quantity * 4)", subtitle: subtitle, label: nil, sectionId: self.section, action: {
                    arguments.createPrepaidGiveaway(prepaidGiveaway)
                })
            case let .adsHeader(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section, linkAction: { _ in
                    arguments.openMonetizationIntro()
                })
            case let .adsProceedsOverview(_, stats, animatedEmoji):
                return StatsOverviewItem(context: arguments.context, presentationData: presentationData, isGroup: false, stats: stats, animatedEmoji: animatedEmoji, sectionId: self.section, style: .blocks)
            case let .adsBalance(_, stats, canWithdraw, isEnabled, animatedEmoji):
                return MonetizationBalanceItem(
                    context: arguments.context,
                    presentationData: presentationData,
                    stats: stats,
                    animatedEmoji: animatedEmoji,
                    canWithdraw: canWithdraw,
                    isEnabled: isEnabled,
                    withdrawAction: {
                        arguments.requestWithdraw()
                    },
                    sectionId: self.section,
                    style: .blocks
                )
            case let .adsBalanceInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section, linkAction: { _ in
                    arguments.openMonetizationInfo()
                })
            case let .adsTransaction(_, theme, transaction):
                let font = Font.regular(presentationData.fontSize.itemListBaseFontSize)
                let smallLabelFont = Font.regular(floor(presentationData.fontSize.itemListBaseFontSize / 17.0 * 13.0))
                var labelColor = theme.list.itemDisclosureActions.constructive.fillColor
           
                let title: NSAttributedString
                let detailText: String
                var detailColor: ItemListDisclosureItemDetailLabelColor = .generic
            
                switch transaction {
                case let .proceeds(_, fromDate, toDate):
                    title = NSAttributedString(string: presentationData.strings.Monetization_Transaction_Proceeds, font: font, textColor: theme.list.itemPrimaryTextColor)
                    let fromDateString = stringForMediumCompactDate(timestamp: fromDate, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
                    let toDateString = stringForMediumCompactDate(timestamp: toDate, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
                    if fromDateString == toDateString {
                        detailText = stringForMediumCompactDate(timestamp: toDate, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: true)
                    } else {
                        detailText = "\(fromDateString) – \(toDateString)"
                    }
                case let .withdrawal(status, _, date, provider, _, _):
                    title = NSAttributedString(string: presentationData.strings.Monetization_Transaction_Withdrawal(provider).string, font: font, textColor: theme.list.itemPrimaryTextColor)
                    labelColor = theme.list.itemDestructiveColor
                    switch status {
                    case .succeed:
                        detailText = stringForMediumCompactDate(timestamp: date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
                    case .failed:
                        detailText = stringForMediumCompactDate(timestamp: date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false) + " – \(presentationData.strings.Monetization_Transaction_Failed)"
                        detailColor = .destructive
                    case .pending:
                        detailText = presentationData.strings.Monetization_Transaction_Pending
                    }
                case let .refund(_, date, _):
                    title = NSAttributedString(string: presentationData.strings.Monetization_Transaction_Refund, font: font, textColor: theme.list.itemPrimaryTextColor)
                    detailText = stringForMediumCompactDate(timestamp: date, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
                }
            
                let label = amountAttributedString(formatBalanceText(transaction.amount, decimalSeparator: presentationData.dateTimeFormat.decimalSeparator, showPlus: true), integralFont: font, fractionalFont: smallLabelFont, color: labelColor).mutableCopy() as! NSMutableAttributedString
                label.append(NSAttributedString(string: " TON", font: smallLabelFont, textColor: labelColor))
                
                return ItemListDisclosureItem(presentationData: presentationData, title: "", attributedTitle: title, label: "", attributedLabel: label, labelStyle: .coloredText(labelColor), additionalDetailLabel: detailText, additionalDetailLabelColor: detailColor, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                    arguments.openTransaction(transaction)
                })
            case let .adsTransactionsExpand(theme, title):
                return ItemListPeerActionItem(presentationData: presentationData, icon: PresentationResourcesItemList.downArrowImage(theme), title: title, sectionId: self.section, editing: false, action: {
                    arguments.expandTransactions()
                })
            case let .adsCpmToggle(_, title, minLevel, value):
                var badgeComponent: AnyComponent<Empty>?
                if value == nil {
                    badgeComponent = AnyComponent(BoostLevelIconComponent(
                        strings: presentationData.strings,
                        level: Int(minLevel)
                    ))
                }
                return ItemListSwitchItem(presentationData: presentationData, title: title, titleBadgeComponent: badgeComponent, value: value == true, enableInteractiveChanges: value != nil, enabled: true, displayLocked: value == nil, sectionId: self.section, style: .blocks, updated: { updatedValue in
                    if value != nil {
                        arguments.updateCpmEnabled(updatedValue)
                    } else {
                        arguments.presentCpmLocked()
                    }
                }, activatedWhileDisabled: {
                    arguments.presentCpmLocked()
                })
        }
    }
}

public enum ChannelStatsSection {
    case stats
    case boosts
    case monetization
}

private struct ChannelStatsControllerState: Equatable {
    let section: ChannelStatsSection
    let boostersExpanded: Bool
    let moreBoostersDisplayed: Int32
    let giftsSelected: Bool
    let transactionsExpanded: Bool
    let moreTransactionsDisplayed: Int32
  
    init() {
        self.section = .stats
        self.boostersExpanded = false
        self.moreBoostersDisplayed = 0
        self.giftsSelected = false
        self.transactionsExpanded = false
        self.moreTransactionsDisplayed = 0
    }
    
    init(section: ChannelStatsSection, boostersExpanded: Bool, moreBoostersDisplayed: Int32, giftsSelected: Bool, transactionsExpanded: Bool, moreTransactionsDisplayed: Int32) {
        self.section = section
        self.boostersExpanded = boostersExpanded
        self.moreBoostersDisplayed = moreBoostersDisplayed
        self.giftsSelected = giftsSelected
        self.transactionsExpanded = transactionsExpanded
        self.moreTransactionsDisplayed = moreTransactionsDisplayed
    }
    
    static func ==(lhs: ChannelStatsControllerState, rhs: ChannelStatsControllerState) -> Bool {
        if lhs.section != rhs.section {
            return false
        }
        if lhs.boostersExpanded != rhs.boostersExpanded {
            return false
        }
        if lhs.moreBoostersDisplayed != rhs.moreBoostersDisplayed {
            return false
        }
        if lhs.giftsSelected != rhs.giftsSelected {
            return false
        }
        if lhs.transactionsExpanded != rhs.transactionsExpanded {
            return false
        }
        if lhs.moreTransactionsDisplayed != rhs.moreTransactionsDisplayed {
            return false
        }
        return true
    }
    
    func withUpdatedSection(_ section: ChannelStatsSection) -> ChannelStatsControllerState {
        return ChannelStatsControllerState(section: section, boostersExpanded: self.boostersExpanded, moreBoostersDisplayed: self.moreBoostersDisplayed, giftsSelected: self.giftsSelected, transactionsExpanded: self.transactionsExpanded, moreTransactionsDisplayed: self.moreTransactionsDisplayed)
    }
    
    func withUpdatedBoostersExpanded(_ boostersExpanded: Bool) -> ChannelStatsControllerState {
        return ChannelStatsControllerState(section: self.section, boostersExpanded: boostersExpanded, moreBoostersDisplayed: self.moreBoostersDisplayed, giftsSelected: self.giftsSelected, transactionsExpanded: self.transactionsExpanded, moreTransactionsDisplayed: self.moreTransactionsDisplayed)
    }
    
    func withUpdatedMoreBoostersDisplayed(_ moreBoostersDisplayed: Int32) -> ChannelStatsControllerState {
        return ChannelStatsControllerState(section: self.section, boostersExpanded: self.boostersExpanded, moreBoostersDisplayed: moreBoostersDisplayed, giftsSelected: self.giftsSelected, transactionsExpanded: self.transactionsExpanded, moreTransactionsDisplayed: self.moreTransactionsDisplayed)
    }
    
    func withUpdatedGiftsSelected(_ giftsSelected: Bool) -> ChannelStatsControllerState {
        return ChannelStatsControllerState(section: self.section, boostersExpanded: self.boostersExpanded, moreBoostersDisplayed: self.moreBoostersDisplayed, giftsSelected: giftsSelected, transactionsExpanded: self.transactionsExpanded, moreTransactionsDisplayed: self.moreTransactionsDisplayed)
    }
    
    func withUpdatedTransactionsExpanded(_ transactionsExpanded: Bool) -> ChannelStatsControllerState {
        return ChannelStatsControllerState(section: self.section, boostersExpanded: self.boostersExpanded, moreBoostersDisplayed: self.moreBoostersDisplayed, giftsSelected: self.giftsSelected, transactionsExpanded: transactionsExpanded, moreTransactionsDisplayed: self.moreTransactionsDisplayed)
    }
    
    func withUpdatedMoreTransactionsDisplayed(_ moreTransactionsDisplayed: Int32) -> ChannelStatsControllerState {
        return ChannelStatsControllerState(section: self.section, boostersExpanded: self.boostersExpanded, moreBoostersDisplayed: self.moreBoostersDisplayed, giftsSelected: self.giftsSelected, transactionsExpanded: self.transactionsExpanded, moreTransactionsDisplayed: moreTransactionsDisplayed)
    }
}

private func statsEntries(
    presentationData: PresentationData,
    data: ChannelStats,
    peer: EnginePeer?,
    messages: [Message]?,
    stories: PeerStoryListContext.State?,
    interactions: [ChannelStatsPostInteractions.PostId: ChannelStatsPostInteractions]?
) -> [StatsEntry] {
    var entries: [StatsEntry] = []
    
    let minDate = stringForDate(timestamp: data.period.minDate, strings: presentationData.strings)
    let maxDate = stringForDate(timestamp: data.period.maxDate, strings: presentationData.strings)
    
    entries.append(.overviewTitle(presentationData.theme, presentationData.strings.Stats_Overview, "\(minDate) – \(maxDate)"))
    entries.append(.overview(presentationData.theme, data))
    
    if !data.growthGraph.isEmpty {
        entries.append(.growthTitle(presentationData.theme, presentationData.strings.Stats_GrowthTitle))
        entries.append(.growthGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.growthGraph, .lines))
    }
    
    if !data.followersGraph.isEmpty {
        entries.append(.followersTitle(presentationData.theme, presentationData.strings.Stats_FollowersTitle))
        entries.append(.followersGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.followersGraph, .lines))
    }
    
    if !data.muteGraph.isEmpty {
        entries.append(.notificationsTitle(presentationData.theme, presentationData.strings.Stats_NotificationsTitle))
        entries.append(.notificationsGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.muteGraph, .lines))
    }
    
    if !data.topHoursGraph.isEmpty {
        entries.append(.viewsByHourTitle(presentationData.theme, presentationData.strings.Stats_ViewsByHoursTitle))
        entries.append(.viewsByHourGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.topHoursGraph, .hourlyStep))
    }
    
    if !data.viewsBySourceGraph.isEmpty {
        entries.append(.viewsBySourceTitle(presentationData.theme, presentationData.strings.Stats_ViewsBySourceTitle))
        entries.append(.viewsBySourceGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.viewsBySourceGraph, .bars))
    }
    
    if !data.newFollowersBySourceGraph.isEmpty {
        entries.append(.followersBySourceTitle(presentationData.theme, presentationData.strings.Stats_FollowersBySourceTitle))
        entries.append(.followersBySourceGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.newFollowersBySourceGraph, .bars))
    }
    
    if !data.languagesGraph.isEmpty {
        entries.append(.languagesTitle(presentationData.theme, presentationData.strings.Stats_LanguagesTitle))
        entries.append(.languagesGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.languagesGraph, .pie))
    }
    
    if !data.interactionsGraph.isEmpty {
        entries.append(.postInteractionsTitle(presentationData.theme, presentationData.strings.Stats_InteractionsTitle))
        entries.append(.postInteractionsGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.interactionsGraph, .twoAxisStep))
    }
    
    if !data.instantPageInteractionsGraph.isEmpty {
        entries.append(.instantPageInteractionsTitle(presentationData.theme, presentationData.strings.Stats_InstantViewInteractionsTitle))
        entries.append(.instantPageInteractionsGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.instantPageInteractionsGraph, .twoAxisStep))
    }
    
    if !data.reactionsByEmotionGraph.isEmpty {
        entries.append(.reactionsByEmotionTitle(presentationData.theme, presentationData.strings.Stats_ReactionsByEmotionTitle))
        entries.append(.reactionsByEmotionGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.reactionsByEmotionGraph, .bars))
    }
    
    if !data.storyInteractionsGraph.isEmpty {
        entries.append(.storyInteractionsTitle(presentationData.theme, presentationData.strings.Stats_StoryInteractionsTitle))
        entries.append(.storyInteractionsGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.storyInteractionsGraph, .twoAxisStep))
    }
    
    if !data.storyReactionsByEmotionGraph.isEmpty {
        entries.append(.storyReactionsByEmotionTitle(presentationData.theme, presentationData.strings.Stats_StoryReactionsByEmotionTitle))
        entries.append(.storyReactionsByEmotionGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.storyReactionsByEmotionGraph, .bars))
    }
    
    if let peer, let interactions {
        var posts: [StatsPostItem] = []
        if let messages {
            for message in messages {
                if let _ = interactions[.message(id: message.id)] {
                    posts.append(.message(message))
                }
            }
        }
        if let stories {
            for story in stories.items {
                if let _ = interactions[.story(peerId: peer.id, id: story.id)] {
                    posts.append(.story(peer, story))
                }
            }
        }
        posts.sort(by: { $0.timestamp > $1.timestamp })
        
        if !posts.isEmpty {
            entries.append(.postsTitle(presentationData.theme, presentationData.strings.Stats_PostsTitle))
            var index: Int32 = 0
            for post in posts {
                switch post {
                case let .message(message):
                    if let interactions = interactions[.message(id: message.id)] {
                        entries.append(.post(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, peer._asPeer(), post, interactions))
                    }
                case let .story(_, story):
                    if let interactions = interactions[.story(peerId: peer.id, id: story.id)] {
                        entries.append(.post(index, presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, peer._asPeer(), post, interactions))
                    }
                }
                index += 1
            }
        }
    }
    return entries
}

private func boostsEntries(
    presentationData: PresentationData,
    state: ChannelStatsControllerState,
    isGroup: Bool,
    boostData: ChannelBoostStatus,
    boostsOnly: Bool,
    boostersState: ChannelBoostersContext.State?,
    giftsState: ChannelBoostersContext.State?,
    giveawayAvailable: Bool
) -> [StatsEntry] {
    var entries: [StatsEntry] = []
    
    if !boostsOnly {
        let progress: CGFloat
        if let nextLevelBoosts = boostData.nextLevelBoosts {
            progress = CGFloat(boostData.boosts - boostData.currentLevelBoosts) / CGFloat(nextLevelBoosts - boostData.currentLevelBoosts)
        } else {
            progress = 1.0
        }
        entries.append(.boostLevel(presentationData.theme, Int32(boostData.boosts), Int32(boostData.level), progress))
    }
    
    entries.append(.boostOverviewTitle(presentationData.theme, presentationData.strings.Stats_Boosts_OverviewHeader))
    entries.append(.boostOverview(presentationData.theme, boostData, isGroup))
    
    if !boostData.prepaidGiveaways.isEmpty {
        entries.append(.boostPrepaidTitle(presentationData.theme, presentationData.strings.Stats_Boosts_PrepaidGiveawaysTitle))
        var i: Int32 = 0
        for giveaway in boostData.prepaidGiveaways {
            entries.append(.boostPrepaid(i, presentationData.theme, presentationData.strings.Stats_Boosts_PrepaidGiveawayCount(giveaway.quantity), presentationData.strings.Stats_Boosts_PrepaidGiveawayMonths("\(giveaway.months)").string, giveaway))
            i += 1
        }
        entries.append(.boostPrepaidInfo(presentationData.theme, presentationData.strings.Stats_Boosts_PrepaidGiveawaysInfo))
    }
    
    let boostersTitle: String
    let boostersPlaceholder: String?
    let boostersFooter: String?
    if let boostersState, boostersState.count > 0 {
        boostersTitle = presentationData.strings.Stats_Boosts_Boosts(boostersState.count)
        boostersPlaceholder = nil
        boostersFooter = isGroup ? presentationData.strings.Stats_Boosts_Group_BoostersInfo : presentationData.strings.Stats_Boosts_BoostersInfo
    } else {
        boostersTitle = presentationData.strings.Stats_Boosts_BoostsNone
        boostersPlaceholder = isGroup ? presentationData.strings.Stats_Boosts_Group_NoBoostersYet : presentationData.strings.Stats_Boosts_NoBoostersYet
        boostersFooter = nil
    }
    entries.append(.boostersTitle(presentationData.theme, boostersTitle))
    
    if let boostersPlaceholder {
        entries.append(.boostersPlaceholder(presentationData.theme, boostersPlaceholder))
    }
    
    var boostsCount: Int32 = 0
    if let boostersState {
        boostsCount = boostersState.count
    }
    var giftsCount: Int32 = 0
    if let giftsState {
        giftsCount = giftsState.count
    }
    
    if boostsCount > 0 && giftsCount > 0 && boostsCount != giftsCount {
        entries.append(.boosterTabs(presentationData.theme, presentationData.strings.Stats_Boosts_TabBoosts(boostsCount), presentationData.strings.Stats_Boosts_TabGifts(giftsCount), state.giftsSelected))
    }
    
    let selectedState: ChannelBoostersContext.State?
    if state.giftsSelected {
        selectedState = giftsState
    } else {
        selectedState = boostersState
    }
    
    if let selectedState {
        var boosterIndex: Int32 = 0
        
        var boosters: [ChannelBoostersContext.State.Boost] = selectedState.boosts
        
        var limit: Int32
        if state.boostersExpanded {
            limit = 25 + state.moreBoostersDisplayed
        } else {
            limit = initialBoostersDisplayedLimit
        }
        boosters = Array(boosters.prefix(Int(limit)))
        
        for booster in boosters {
            entries.append(.booster(boosterIndex, presentationData.theme, presentationData.dateTimeFormat, booster))
            boosterIndex += 1
        }
        
        let totalBoostsCount = boosters.reduce(Int32(0)) { partialResult, boost in
            return partialResult + boost.multiplier
        }
        
        if totalBoostsCount < selectedState.count {
            let moreCount: Int32
            if !state.boostersExpanded {
                moreCount = min(80, selectedState.count - totalBoostsCount)
            } else {
                moreCount = min(200, selectedState.count - totalBoostsCount)
            }
            entries.append(.boostersExpand(presentationData.theme, presentationData.strings.Stats_Boosts_ShowMoreBoosts(moreCount)))
        }
    }
    
    if let boostersFooter {
        entries.append(.boostersInfo(presentationData.theme, boostersFooter))
    }
    
    entries.append(.boostLinkTitle(presentationData.theme, presentationData.strings.Stats_Boosts_LinkHeader))
    entries.append(.boostLink(presentationData.theme, boostData.url))
    entries.append(.boostLinkInfo(presentationData.theme, isGroup ? presentationData.strings.Stats_Boosts_Group_LinkInfo : presentationData.strings.Stats_Boosts_LinkInfo))
    
    if giveawayAvailable {
        entries.append(.boostGifts(presentationData.theme, presentationData.strings.Stats_Boosts_GetBoosts))
        entries.append(.boostGiftsInfo(presentationData.theme, isGroup ? presentationData.strings.Stats_Boosts_Group_GetBoostsInfo : presentationData.strings.Stats_Boosts_GetBoostsInfo))
    }
    return entries
}

private func monetizationEntries(
    presentationData: PresentationData,
    state: ChannelStatsControllerState,
    peer: EnginePeer?,
    data: RevenueStats,
    boostData: ChannelBoostStatus?,
    transactionsInfo: RevenueStatsTransactionsContext.State,
    adsRestricted: Bool,
    animatedEmojis: [String: [StickerPackItem]],
    premiumConfiguration: PremiumConfiguration,
    monetizationConfiguration: MonetizationConfiguration
) -> [StatsEntry] {
    let diamond = animatedEmojis["💎"]?.first?.file
    
    var entries: [StatsEntry] = []
    entries.append(.adsHeader(presentationData.theme, presentationData.strings.Monetization_Header))
    
    entries.append(.adsImpressionsTitle(presentationData.theme, presentationData.strings.Monetization_ImpressionsTitle))
    if !data.topHoursGraph.isEmpty {
        entries.append(.adsImpressionsGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.topHoursGraph, .hourlyStep))
    }
    
    entries.append(.adsRevenueTitle(presentationData.theme, presentationData.strings.Monetization_AdRevenueTitle))
    if !data.revenueGraph.isEmpty {
        entries.append(.adsRevenueGraph(presentationData.theme, presentationData.strings, presentationData.dateTimeFormat, data.revenueGraph, .currency, data.usdRate))
    }
        
    entries.append(.adsProceedsTitle(presentationData.theme, presentationData.strings.Monetization_OverviewTitle))
    entries.append(.adsProceedsOverview(presentationData.theme, data, diamond))
    
    var isCreator = false
    if let peer, case let .channel(channel) = peer, channel.flags.contains(.isCreator) {
        isCreator = true
    }
    entries.append(.adsBalanceTitle(presentationData.theme, presentationData.strings.Monetization_BalanceTitle))
    entries.append(.adsBalance(presentationData.theme, data, isCreator && data.availableBalance > 0, monetizationConfiguration.withdrawalAvailable, diamond))

    if isCreator {
        let withdrawalInfoText: String
        if data.availableBalance == 0 {
            withdrawalInfoText = presentationData.strings.Monetization_Balance_ZeroInfo
        } else if monetizationConfiguration.withdrawalAvailable {
            withdrawalInfoText = presentationData.strings.Monetization_Balance_AvailableInfo
        } else {
            withdrawalInfoText = presentationData.strings.Monetization_Balance_ComingLaterInfo
        }
        entries.append(.adsBalanceInfo(presentationData.theme, withdrawalInfoText))
    }

    if !transactionsInfo.transactions.isEmpty {
        entries.append(.adsTransactionsTitle(presentationData.theme, presentationData.strings.Monetization_TransactionsTitle))
        
        var transactions = transactionsInfo.transactions
        var limit: Int32
        if state.transactionsExpanded {
            limit = 25 + state.moreTransactionsDisplayed
        } else {
            limit = initialTransactionsDisplayedLimit
        }
        transactions = Array(transactions.prefix(Int(limit)))
        
        var i: Int32 = 0
        for transaction in transactions {
            entries.append(.adsTransaction(i, presentationData.theme, transaction))
            i += 1
        }
        
        if transactions.count < transactionsInfo.count {
            let moreCount: Int32
            if !state.transactionsExpanded {
                moreCount = min(20, transactionsInfo.count - Int32(transactions.count))
            } else {
                moreCount = min(500, transactionsInfo.count - Int32(transactions.count))
            }
            entries.append(.adsTransactionsExpand(presentationData.theme, presentationData.strings.Monetization_Transaction_ShowMoreTransactions(moreCount)))
        }
    }
    
    if isCreator {
        var switchOffAdds: Bool? = nil
        if let boostData, boostData.level >= premiumConfiguration.minChannelRestrictAdsLevel {
            switchOffAdds = adsRestricted
        }
        
        entries.append(.adsCpmToggle(presentationData.theme, presentationData.strings.Monetization_SwitchOffAds, premiumConfiguration.minChannelRestrictAdsLevel, switchOffAdds))
        entries.append(.adsCpmInfo(presentationData.theme, presentationData.strings.Monetization_SwitchOffAdsInfo))
    }
    
    return entries
}

private func channelStatsControllerEntries(
    presentationData: PresentationData,
    state: ChannelStatsControllerState,
    peer: EnginePeer?,
    data: ChannelStats?,
    messages: [Message]?,
    stories: PeerStoryListContext.State?,
    interactions: [ChannelStatsPostInteractions.PostId: ChannelStatsPostInteractions]?, 
    boostData: ChannelBoostStatus?,
    boostersState: ChannelBoostersContext.State?,
    giftsState: ChannelBoostersContext.State?,
    giveawayAvailable: Bool,
    isGroup: Bool,
    boostsOnly: Bool,
    animatedEmojis: [String: [StickerPackItem]],
    revenueState: RevenueStats?,
    revenueTransactions: RevenueStatsTransactionsContext.State,
    adsRestricted: Bool,
    premiumConfiguration: PremiumConfiguration,
    monetizationConfiguration: MonetizationConfiguration
) -> [StatsEntry] {
    switch state.section {
    case .stats:
        if let data {
            return statsEntries(
                presentationData: presentationData,
                data: data,
                peer: peer,
                messages: messages,
                stories: stories,
                interactions: interactions
            )
        }
    case .boosts:
        if let boostData {
            return boostsEntries(
                presentationData: presentationData,
                state: state,
                isGroup: isGroup,
                boostData: boostData,
                boostsOnly: boostsOnly,
                boostersState: boostersState,
                giftsState: giftsState,
                giveawayAvailable: giveawayAvailable
            )
        }
    case .monetization:
        if let revenueState {
            return monetizationEntries(
                presentationData: presentationData,
                state: state,
                peer: peer,
                data: revenueState,
                boostData: boostData,
                transactionsInfo: revenueTransactions,
                adsRestricted: adsRestricted,
                animatedEmojis: animatedEmojis,
                premiumConfiguration: premiumConfiguration,
                monetizationConfiguration: monetizationConfiguration
            )
        }
    }
    return []
}

public func channelStatsController(context: AccountContext, updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil, peerId: PeerId, section: ChannelStatsSection = .stats, boostStatus: ChannelBoostStatus? = nil, boostStatusUpdated: ((ChannelBoostStatus) -> Void)? = nil) -> ViewController {
    let statePromise = ValuePromise(ChannelStatsControllerState(section: section, boostersExpanded: false, moreBoostersDisplayed: 0, giftsSelected: false, transactionsExpanded: false, moreTransactionsDisplayed: 0), ignoreRepeated: true)
    let stateValue = Atomic(value: ChannelStatsControllerState(section: section, boostersExpanded: false, moreBoostersDisplayed: 0, giftsSelected: false, transactionsExpanded: false, moreTransactionsDisplayed: 0))
    let updateState: ((ChannelStatsControllerState) -> ChannelStatsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    let premiumConfiguration = PremiumConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    let monetizationConfiguration = MonetizationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    
    var openPostStatsImpl: ((EnginePeer, StatsPostItem) -> Void)?
    var openStoryImpl: ((EngineStoryItem, UIView) -> Void)?
    var contextActionImpl: ((MessageId, ASDisplayNode, ContextGesture?) -> Void)?
    
    let actionsDisposable = DisposableSet()    
    let dataPromise = Promise<ChannelStats?>(nil)
    let messagesPromise = Promise<MessageHistoryView?>(nil)
    
    let storiesPromise = Promise<PeerStoryListContext.State?>()
            
    let statsContext = ChannelStatsContext(postbox: context.account.postbox, network: context.account.network, peerId: peerId)
    let dataSignal: Signal<ChannelStats?, NoError> = statsContext.state
    |> map { state in
        return state.stats
    } |> afterNext({ [weak statsContext] stats in
        if let statsContext = statsContext, let stats = stats {
            if case .OnDemand = stats.interactionsGraph {
                statsContext.loadInteractionsGraph()
                statsContext.loadMuteGraph()
                statsContext.loadTopHoursGraph()
                statsContext.loadNewFollowersBySourceGraph()
                statsContext.loadViewsBySourceGraph()
                statsContext.loadLanguagesGraph()
                statsContext.loadInstantPageInteractionsGraph()
                statsContext.loadReactionsByEmotionGraph()
                statsContext.loadStoryInteractionsGraph()
                statsContext.loadStoryReactionsByEmotionGraph()
            }
        }
    })
    dataPromise.set(.single(nil) |> then(dataSignal))
    
    let boostDataPromise = Promise<ChannelBoostStatus?>()
    boostDataPromise.set(.single(boostStatus) |> then(context.engine.peers.getChannelBoostStatus(peerId: peerId)))
    
    actionsDisposable.add((boostDataPromise.get()
    |> deliverOnMainQueue).start(next: { boostStatus in
        if let boostStatus, let boostStatusUpdated {
            boostStatusUpdated(boostStatus)
        }
    }))

    let boostsContext = ChannelBoostersContext(account: context.account, peerId: peerId, gift: false)
    let giftsContext = ChannelBoostersContext(account: context.account, peerId: peerId, gift: true)
    let revenueContext = RevenueStatsContext(postbox: context.account.postbox, network: context.account.network, peerId: peerId)
    let revenueState = Promise<RevenueStatsContextState?>()
    revenueState.set(.single(nil) |> then(revenueContext.state |> map(Optional.init)))
    
    let revenueTransactions = RevenueStatsTransactionsContext(account: context.account, peerId: peerId)
    
    var dismissAllTooltipsImpl: (() -> Void)?
    var presentImpl: ((ViewController) -> Void)?
    var pushImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var navigateToChatImpl: ((EnginePeer) -> Void)?
    var navigateToMessageImpl: ((EngineMessage.Id) -> Void)?
    var openBoostImpl: ((Bool) -> Void)?
    var openTransactionImpl: ((RevenueStatsTransactionsContext.State.Transaction) -> Void)?
    var requestWithdrawImpl: (() -> Void)?
    var updateStatusBarImpl: ((StatusBarStyle) -> Void)?
    var dismissInputImpl: (() -> Void)?
    
    let arguments = ChannelStatsControllerArguments(context: context, loadDetailedGraph: { graph, x -> Signal<StatsGraph?, NoError> in
        return statsContext.loadDetailedGraph(graph, x: x)
    }, openPostStats: { peer, item in
        openPostStatsImpl?(peer, item)
    }, openStory: { story, sourceView in
        openStoryImpl?(story, sourceView)
    }, contextAction: { messageId, node, gesture in
        contextActionImpl?(messageId, node, gesture)
    }, copyBoostLink: { link in
        UIPasteboard.general.string = link
                
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(text: presentationData.strings.ChannelBoost_BoostLinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
    }, shareBoostLink: { link in        
        let shareController = ShareController(context: context, subject: .url(link), updatedPresentationData: updatedPresentationData)
        shareController.completed = {  peerIds in
            let _ = (context.engine.data.get(
                EngineDataList(
                    peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)
                )
            )
            |> deliverOnMainQueue).start(next: { peerList in
                let peers = peerList.compactMap { $0 }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                
                let text: String
                var savedMessages = false
                if peerIds.count == 1, let peerId = peerIds.first, peerId == context.account.peerId {
                    text = presentationData.strings.ChannelBoost_BoostLinkForwardTooltip_SavedMessages_One
                    savedMessages = true
                } else {
                    if peers.count == 1, let peer = peers.first {
                        let peerName = peer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        text = presentationData.strings.ChannelBoost_BoostLinkForwardTooltip_Chat_One(peerName).string
                    } else if peers.count == 2, let firstPeer = peers.first, let secondPeer = peers.last {
                        let firstPeerName = firstPeer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : firstPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        let secondPeerName = secondPeer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : secondPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        text = presentationData.strings.ChannelBoost_BoostLinkForwardTooltip_TwoChats_One(firstPeerName, secondPeerName).string
                    } else if let peer = peers.first {
                        let peerName = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        text = presentationData.strings.ChannelBoost_BoostLinkForwardTooltip_ManyChats_One(peerName, "\(peers.count - 1)").string
                    } else {
                        text = ""
                    }
                }
                
                presentImpl?(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: savedMessages, text: text), elevatedLayout: false, animateInAsReplacement: true, action: { action in
                    if savedMessages, action == .info {
                        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
                        |> deliverOnMainQueue).start(next: { peer in
                            guard let peer else {
                                return
                            }
                            navigateToChatImpl?(peer)
                        })
                    }
                    return false
                }))
            })
        }
        shareController.actionCompleted = {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(text: presentationData.strings.ChannelBoost_BoostLinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
        }
        presentImpl?(shareController)
    },
    openBoost: { boost in
        dismissAllTooltipsImpl?()
        
        if let peer = boost.peer, !boost.flags.contains(.isGiveaway) && !boost.flags.contains(.isGift) {
            navigateToChatImpl?(peer)
            return
        }
        
        if boost.peer == nil, boost.flags.contains(.isGiveaway) && !boost.flags.contains(.isUnclaimed) {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: presentationData.strings.Stats_Boosts_TooltipToBeDistributed, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
            return
        }
        
        let controller = PremiumGiftCodeScreen(
            context: context,
            subject: .boost(peerId, boost),
            action: {},
            openPeer: { peer in
                navigateToChatImpl?(peer)
            },
            openMessage: { messageId in
                navigateToMessageImpl?(messageId)
            })
        pushImpl?(controller)
    },
    expandBoosters: {
        var giftsSelected = false
        updateState { state in
            giftsSelected = state.giftsSelected
            if state.boostersExpanded {
                return state.withUpdatedMoreBoostersDisplayed(state.moreBoostersDisplayed + 50)
            } else {
                return state.withUpdatedBoostersExpanded(true)
            }
        }
        if giftsSelected {
            giftsContext.loadMore()
        } else {
            boostsContext.loadMore()
        }
    },
    openGifts: {
        let controller = createGiveawayController(context: context, peerId: peerId, subject: .generic)
        pushImpl?(controller)
    },
    createPrepaidGiveaway: { prepaidGiveaway in
        let controller = createGiveawayController(context: context, peerId: peerId, subject: .prepaid(prepaidGiveaway))
        pushImpl?(controller)
    },
    updateGiftsSelected: { selected in
        updateState { $0.withUpdatedGiftsSelected(selected).withUpdatedBoostersExpanded(false) }
    },
    requestWithdraw: {
        requestWithdrawImpl?()
    },
    openMonetizationIntro: {
        let controller = MonetizationIntroScreen(context: context, openMore: {})
        pushImpl?(controller)
    },
    openMonetizationInfo: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: presentationData.strings.Monetization_BalanceInfo_URL, forceExternal: true, presentationData: presentationData, navigationController: nil, dismissInput: {})
    },
    openTransaction: { transaction in
        openTransactionImpl?(transaction)
    },
    expandTransactions: {
        updateState { state in
            if state.transactionsExpanded {
                return state.withUpdatedMoreTransactionsDisplayed(state.moreTransactionsDisplayed + 50)
            } else {
                return state.withUpdatedTransactionsExpanded(true)
            }
        }
        revenueTransactions.loadMore()
    },
    updateCpmEnabled: { value in
        let _ = context.engine.peers.updateChannelRestrictAdMessages(peerId: peerId, restricted: value).start()
    },
    presentCpmLocked: {
        let _ = combineLatest(
            queue: Queue.mainQueue(),
            context.engine.peers.getChannelBoostStatus(peerId: peerId),
            context.engine.peers.getMyBoostStatus()
        ).startStandalone(next: { boostStatus, myBoostStatus in
            guard let boostStatus, let myBoostStatus else {
                return
            }
            boostDataPromise.set(.single(boostStatus))
            
            let controller = context.sharedContext.makePremiumBoostLevelsController(context: context, peerId: peerId, subject: .noAds, boostStatus: boostStatus, myBoostStatus: myBoostStatus, forceDark: false, openStats: nil)
            pushImpl?(controller)
        })
    },
    dismissInput: {
        dismissInputImpl?()
    })
    
    let messageView = context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 200, fixedCombinedReadStates: nil)
    |> map { messageHistoryView, _, _ -> MessageHistoryView? in
        return messageHistoryView
    }
    messagesPromise.set(.single(nil) |> then(messageView))
    
    let storyList = PeerStoryListContext(account: context.account, peerId: peerId, isArchived: false)
    storyList.loadMore()
    storiesPromise.set(
        .single(nil) 
        |> then(
            storyList.state
            |> map(Optional.init)
        )
    )
    
    let peer = Promise<EnginePeer?>()
    peer.set(context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)))
    
    let peerData = context.engine.data.get(
         TelegramEngine.EngineData.Item.Peer.AdsRestricted(id: peerId),
         TelegramEngine.EngineData.Item.Peer.CanViewRevenue(id: peerId)
    )
    
    let longLoadingSignal: Signal<Bool, NoError> = .single(false) |> then(.single(true) |> delay(2.0, queue: Queue.mainQueue()))
    let previousData = Atomic<ChannelStats?>(value: nil)

    let presentationData = updatedPresentationData?.signal ?? context.sharedContext.presentationData
    let signal = combineLatest(
        presentationData,
        statePromise.get(),
        peer.get(),
        dataPromise.get(),
        messagesPromise.get(),
        storiesPromise.get(),
        boostDataPromise.get(),
        boostsContext.state,
        giftsContext.state,
        revenueState.get(),
        revenueTransactions.state,
        peerData,
        longLoadingSignal,
        context.animatedEmojiStickers
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, peer, data, messageView, stories, boostData, boostersState, giftsState, revenueState, revenueTransactions, peerData, longLoading, animatedEmojiStickers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (adsRestricted, canViewRevenue) = peerData
        
        var isGroup = false
        if let peer, case let .channel(channel) = peer, case .group = channel.info {
            isGroup = true
        }
        
        let previous = previousData.swap(data)
        var emptyStateItem: ItemListControllerEmptyStateItem?
        switch state.section {
        case .stats:
            if data == nil {
                if longLoading {
                    emptyStateItem = StatsEmptyStateItem(context: context, theme: presentationData.theme, strings: presentationData.strings)
                } else {
                    emptyStateItem = ItemListLoadingIndicatorEmptyStateItem(theme: presentationData.theme)
                }
            }
        case .boosts:
            if boostData == nil {
                emptyStateItem = ItemListLoadingIndicatorEmptyStateItem(theme: presentationData.theme)
            }
        case .monetization:
            if revenueState?.stats == nil {
                emptyStateItem = ItemListLoadingIndicatorEmptyStateItem(theme: presentationData.theme)
            }
        }
        
        var existingGroupingKeys = Set<Int64>()
        var idsToFilter = Set<MessageId>()
        var messages = messageView?.entries.map { $0.message } ?? []
        for message in messages {
            if let groupingKey = message.groupingKey {
                if existingGroupingKeys.contains(groupingKey) {
                    idsToFilter.insert(message.id)
                } else {
                    existingGroupingKeys.insert(groupingKey)
                }
            }
        }
        messages = messages.filter { !idsToFilter.contains($0.id) }.sorted(by: { (lhsMessage, rhsMessage) -> Bool in
            return lhsMessage.timestamp > rhsMessage.timestamp
        })
        let interactions = data?.postInteractions.reduce([ChannelStatsPostInteractions.PostId : ChannelStatsPostInteractions]()) { (map, interactions) -> [ChannelStatsPostInteractions.PostId : ChannelStatsPostInteractions] in
            var map = map
            map[interactions.postId] = interactions
            return map
        }
                
        var title: ItemListControllerTitle
        var headerItem: BoostHeaderItem?
        var leftNavigationButton: ItemListNavigationButton?
        var boostsOnly = false
        if section == .boosts {
            title = .text("")
            
            let headerTitle = isGroup ? presentationData.strings.GroupBoost_Title : presentationData.strings.ChannelBoost_Title
            let headerText = isGroup ? presentationData.strings.GroupBoost_Info : presentationData.strings.ChannelBoost_Info
            
            headerItem = BoostHeaderItem(context: context, theme: presentationData.theme, strings: presentationData.strings, status: boostData, title: headerTitle, text: headerText, openBoost: {
                openBoostImpl?(false)
            }, createGiveaway: {
                arguments.openGifts()
            }, openFeatures: {
                openBoostImpl?(true)
            }, back: {
                dismissImpl?()
            }, updateStatusBar: { style in
                updateStatusBarImpl?(style)
            })
            leftNavigationButton = ItemListNavigationButton(content: .none, style: .regular, enabled: false, action: {})
            boostsOnly = true
        } else {
            var index: Int
            switch state.section {
            case .stats:
                index = 0
            case .boosts:
                index = 1
            case .monetization:
                index = 2
            }
            var tabs: [String] = []
            tabs.append(presentationData.strings.Stats_Statistics)
            tabs.append(presentationData.strings.Stats_Boosts)
            if canViewRevenue {
                tabs.append(presentationData.strings.Stats_Monetization)
            }
            title = .textWithTabs(peer?.compactDisplayTitle ?? "", tabs, index)
        }
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: title, leftNavigationButton: leftNavigationButton, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: channelStatsControllerEntries(presentationData: presentationData, state: state, peer: peer, data: data, messages: messages, stories: stories, interactions: interactions, boostData: boostData, boostersState: boostersState, giftsState: giftsState, giveawayAvailable: premiumConfiguration.giveawayGiftsPurchaseAvailable, isGroup: isGroup, boostsOnly: boostsOnly, animatedEmojis: animatedEmojiStickers, revenueState: revenueState?.stats, revenueTransactions: revenueTransactions, adsRestricted: adsRestricted, premiumConfiguration: premiumConfiguration, monetizationConfiguration: monetizationConfiguration), style: .blocks, emptyStateItem: emptyStateItem, headerItem: headerItem, crossfadeState: previous == nil, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
        let _ = statsContext.state
        let _ = storyList.state
        let _ = revenueContext.state
    }
    
    let controller = ItemListController(context: context, state: signal)
    controller.contentOffsetChanged = { [weak controller] _, _ in
        controller?.forEachItemNode({ itemNode in
            if let itemNode = itemNode as? StatsGraphItemNode {
                itemNode.resetInteraction()
            }
        })
    }
    controller.titleControlValueChanged = { value in
        updateState { state in
            let section: ChannelStatsSection
            switch value {
            case 0:
                section = .stats
            case 1:
                section = .boosts
            case 2:
                section = .monetization
                let _ = (ApplicationSpecificNotice.monetizationIntroDismissed(accountManager: context.sharedContext.accountManager)
                |> deliverOnMainQueue).start(next: { dismissed in
                    if !dismissed {
                        arguments.openMonetizationIntro()
                        let _ = ApplicationSpecificNotice.setMonetizationIntroDismissed(accountManager: context.sharedContext.accountManager).start()
                    }
                })
            default:
                section = .stats
            }
            return state.withUpdatedSection(section)
        }
    }
    controller.didDisappear = { [weak controller] _ in
        controller?.clearItemNodesHighlight(animated: true)
    }
    openPostStatsImpl = { [weak controller] peer, post in
        let subject: StatsSubject
        switch post {
        case let .message(message):
            subject = .message(id: message.id)
        case let .story(_, story):
            subject = .story(peerId: peerId, id: story.id, item: story, fromStory: false)
        }
        controller?.push(messageStatsController(context: context, subject: subject))
    }
    openStoryImpl = { [weak controller] story, sourceView in
        let storyContent = SingleStoryContentContextImpl(context: context, storyId: StoryId(peerId: peerId, id: story.id), storyItem: story, readGlobally: false)
        let _ = (storyContent.state
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak controller, weak sourceView] _ in
            guard let controller, let sourceView else {
                return
            }
            let transitionIn = StoryContainerScreen.TransitionIn(
                sourceView: sourceView,
                sourceRect: sourceView.bounds,
                sourceCornerRadius: sourceView.bounds.width * 0.5,
                sourceIsAvatar: false
            )
        
            let storyContainerScreen = StoryContainerScreen(
                context: context,
                content: storyContent,
                transitionIn: transitionIn,
                transitionOut: { [weak sourceView] peerId, storyIdValue in
                    if let sourceView {
                        let destinationView = sourceView
                        return StoryContainerScreen.TransitionOut(
                            destinationView: destinationView,
                            transitionView: StoryContainerScreen.TransitionView(
                                makeView: { [weak destinationView] in
                                    let parentView = UIView()
                                    if let copyView = destinationView?.snapshotContentTree(unhide: true) {
                                        parentView.addSubview(copyView)
                                    }
                                    return parentView
                                },
                                updateView: { copyView, state, transition in
                                    guard let view = copyView.subviews.first else {
                                        return
                                    }
                                    let size = state.sourceSize.interpolate(to: state.destinationSize, amount: state.progress)
                                    transition.setPosition(view: view, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
                                    transition.setScale(view: view, scale: size.width / state.destinationSize.width)
                                },
                                insertCloneTransitionView: nil
                            ),
                            destinationRect: destinationView.bounds,
                            destinationCornerRadius: destinationView.bounds.width * 0.5,
                            destinationIsAvatar: false,
                            completed: { [weak sourceView] in
                                guard let sourceView else {
                                    return
                                }
                                sourceView.isHidden = false
                            }
                        )
                    } else {
                        return nil
                    }
                }
            )
            controller.push(storyContainerScreen)
        })
    }
    contextActionImpl = { [weak controller] messageId, sourceNode, gesture in
        guard let controller = controller, let sourceNode = sourceNode as? ContextExtractedContentContainingNode else {
            return
        }
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        var items: [ContextMenuItem] = []
        items.append(.action(ContextMenuActionItem(text: presentationData.strings.Conversation_ViewInChannel, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/GoToMessage"), color: theme.contextMenu.primaryColor) }, action: { [weak controller] c, _ in
            c.dismiss(completion: {
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> deliverOnMainQueue).start(next: { peer in
                    guard let peer = peer else {
                        return
                    }
                    
                    if let navigationController = controller?.navigationController as? NavigationController {
                        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil)))
                    }
                })
            })
        })))
        
        let contextController = ContextController(presentationData: presentationData, source: .extracted(ChannelStatsContextExtractedContentSource(controller: controller, sourceNode: sourceNode, keepInPlace: false)), items: .single(ContextController.Items(content: .list(items))), gesture: gesture)
        controller.presentInGlobalOverlay(contextController)
    }
    dismissAllTooltipsImpl = { [weak controller] in
        if let controller {
            controller.window?.forEachController({ controller in
                if let controller = controller as? UndoOverlayController {
                    controller.dismiss()
                }
            })
            controller.forEachController({ controller in
                if let controller = controller as? UndoOverlayController {
                    controller.dismiss()
                }
                return true
            })
        }
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    navigateToChatImpl = { [weak controller] peer in
        if let navigationController = controller?.navigationController as? NavigationController {
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), keepStack: .always, purposefulAction: {}, peekData: nil, forceOpenChat: true))
        }
    }
    navigateToMessageImpl = { [weak controller] messageId in
        let _ = (context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: messageId.peerId)
        )
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer = peer else {
                return
            }
            if let navigationController = controller?.navigationController as? NavigationController {
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil), keepStack: .always, useExisting: false, purposefulAction: {}, peekData: nil))
            }
        })
    }
    openBoostImpl = { features in
        if features {
            let boostController = PremiumBoostLevelsScreen(
                context: context,
                peerId: peerId,
                mode: .features,
                status: nil,
                myBoostStatus: nil
            )
            pushImpl?(boostController)
        } else {
            let _ = combineLatest(
                queue: Queue.mainQueue(),
                context.engine.peers.getChannelBoostStatus(peerId: peerId),
                context.engine.peers.getMyBoostStatus()
            ).startStandalone(next: { boostStatus, myBoostStatus in
                guard let boostStatus, let myBoostStatus else {
                    return
                }
                boostDataPromise.set(.single(boostStatus))
                
                let boostController = PremiumBoostLevelsScreen(
                    context: context,
                    peerId: peerId,
                    mode: .owner(subject: nil),
                    status: boostStatus,
                    myBoostStatus: myBoostStatus,
                    openGift: {
                        let giveawayController = createGiveawayController(context: context, peerId: peerId, subject: .generic)
                        pushImpl?(giveawayController)
                    }
                )
                boostController.boostStatusUpdated = { boostStatus, _ in
                    boostDataPromise.set(.single(boostStatus))
                }
                pushImpl?(boostController)
            })
        }
    }
    requestWithdrawImpl = {
        let controller = revenueWithdrawalController(context: context, updatedPresentationData: updatedPresentationData, peerId: peerId, present: { c, _ in
            presentImpl?(c)
        }, completion: { [weak revenueContext] url in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: true, presentationData: presentationData, navigationController: nil, dismissInput: {})
            
            revenueContext?.reload()
        })
        presentImpl?(controller)
    }
    openTransactionImpl = { transaction in
        let _ = (peer.get()
        |> take(1)
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer else {
                return
            }
            pushImpl?(TransactionInfoScreen(context: context, peer: peer, transaction: transaction, openExplorer: { url in
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: true, presentationData: context.sharedContext.currentPresentationData.with { $0 }, navigationController: nil, dismissInput: {})
            }))
        })
    }
    updateStatusBarImpl = { [weak controller] style in
        controller?.setStatusBarStyle(style, animated: true)
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    return controller
}

final class ChannelStatsContextExtractedContentSource: ContextExtractedContentSource {
    var keepInPlace: Bool
    let ignoreContentTouches: Bool = true
    let blurBackground: Bool = true
    
    private let controller: ViewController
    private let sourceNode: ContextExtractedContentContainingNode
    
    init(controller: ViewController, sourceNode: ContextExtractedContentContainingNode, keepInPlace: Bool) {
        self.controller = controller
        self.sourceNode = sourceNode
        self.keepInPlace = keepInPlace
    }
    
    func takeView() -> ContextControllerTakeViewInfo? {
        return ContextControllerTakeViewInfo(containingItem: .node(self.sourceNode), contentAreaInScreenSpace: UIScreen.main.bounds)
    }
    
    func putBack() -> ContextControllerPutBackViewInfo? {
        return ContextControllerPutBackViewInfo(contentAreaInScreenSpace: UIScreen.main.bounds)
    }
}

private struct MonetizationConfiguration {
    static var defaultValue: MonetizationConfiguration {
        return MonetizationConfiguration(withdrawalAvailable: false)
    }
    
    public let withdrawalAvailable: Bool
    
    fileprivate init(withdrawalAvailable: Bool) {
        self.withdrawalAvailable = withdrawalAvailable
    }
    
    static func with(appConfiguration: AppConfiguration) -> MonetizationConfiguration {
        if let data = appConfiguration.data, let withdrawalAvailable = data["channel_revenue_withdrawal_enabled"] as? Bool {
            return MonetizationConfiguration(withdrawalAvailable: withdrawalAvailable)
        } else {
            return .defaultValue
        }
    }
}
