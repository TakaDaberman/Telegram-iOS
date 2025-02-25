import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

private class AdMessagesHistoryContextImpl {
    final class CachedMessage: Equatable, Codable {
        enum CodingKeys: String, CodingKey {
            case opaqueId
            case messageType
            case displayAvatar
            case text
            case textEntities
            case media
            case target
            case messageId
            case startParam
            case buttonText
            case sponsorInfo
            case additionalInfo
            case canReport
        }
        
        enum MessageType: Int32, Codable {
            case sponsored = 0
            case recommended = 1
        }
        
        enum Target: Equatable, Codable {
            enum DecodingError: Error {
                case generic
            }
            
            enum CodingKeys: String, CodingKey {
                case peer
                case invite
                case webPage
                case botApp
            }
            
            struct Invite: Equatable, Codable {
                enum CodingKeys: String, CodingKey {
                    case title
                    case joinHash
                    case nameColor
                    case image
                    case peer
                }
                
                var title: String
                var joinHash: String
                var nameColor: PeerNameColor?
                var image: TelegramMediaImage?
                var peer: Peer?
                
                init(title: String, joinHash: String, nameColor: PeerNameColor?, image: TelegramMediaImage?, peer: Peer?) {
                    self.title = title
                    self.joinHash = joinHash
                    self.nameColor = nameColor
                    self.image = image
                    self.peer = peer
                }
                
                static func ==(lhs: Invite, rhs: Invite) -> Bool {
                    if lhs.title != rhs.title {
                        return false
                    }
                    if lhs.joinHash != rhs.joinHash {
                        return false
                    }
                    if lhs.nameColor != rhs.nameColor {
                        return false
                    }
                    if lhs.image != rhs.image {
                        return false
                    }
                    if !arePeersEqual(lhs.peer, rhs.peer) {
                        return false
                    }
                    return true
                }
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                   
                    self.title = try container.decode(String.self, forKey: .title)
                    self.joinHash = try container.decode(String.self, forKey: .joinHash)
                    self.nameColor = try container.decodeIfPresent(Int32.self, forKey: .nameColor).flatMap { PeerNameColor(rawValue: $0) }
                    self.image = (try container.decodeIfPresent(Data.self, forKey: .image)).flatMap { data in
                        return TelegramMediaImage(decoder: PostboxDecoder(buffer: MemoryBuffer(data: data)))
                    }
                    self.peer = (try container.decodeIfPresent(Data.self, forKey: .peer)).flatMap { data in
                        return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? Peer
                    }
                }
                
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                   
                    try container.encode(self.title, forKey: .title)
                    try container.encode(self.joinHash, forKey: .joinHash)
                    try container.encodeIfPresent(self.nameColor?.rawValue, forKey: .nameColor)
                    try container.encodeIfPresent(self.image.flatMap { image in
                        let encoder = PostboxEncoder()
                        image.encode(encoder)
                        return encoder.makeData()
                    }, forKey: .image)
                    try container.encodeIfPresent(self.peer.flatMap { peer in
                        let encoder = PostboxEncoder()
                        encoder.encodeRootObject(peer)
                        return encoder.makeData()
                    }, forKey: .peer)
                }
            }
            
            struct WebPage: Equatable, Codable {
                var title: String
                var url: String
                var photo: TelegramMediaImage?
            }
            
            case peer(PeerId)
            case invite(Invite)
            case webPage(WebPage)
            case botApp(PeerId, BotApp)
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                if let botApp = try container.decodeIfPresent(BotApp.self, forKey: .botApp), let peer = try container.decodeIfPresent(Int64.self, forKey: .peer) {
                    self = .botApp(PeerId(peer), botApp)
                } else if let peer = try container.decodeIfPresent(Int64.self, forKey: .peer) {
                    self = .peer(PeerId(peer))
                } else if let invite = try container.decodeIfPresent(Invite.self, forKey: .invite) {
                    self = .invite(invite)
                } else if let webPage = try container.decodeIfPresent(WebPage.self, forKey: .webPage) {
                    self = .webPage(webPage)
                } else {
                    throw DecodingError.generic
                }
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                
                switch self {
                case let .peer(peerId):
                    try container.encode(peerId.toInt64(), forKey: .peer)
                case let .invite(invite):
                    try container.encode(invite, forKey: .invite)
                case let .webPage(webPage):
                    try container.encode(webPage, forKey: .webPage)
                case let .botApp(peerId, botApp):
                    try container.encode(peerId.toInt64(), forKey: .peer)
                    try container.encode(botApp, forKey: .botApp)
                }
            }
        }

        public let opaqueId: Data
        public let messageType: MessageType
        public let displayAvatar: Bool
        public let text: String
        public let textEntities: [MessageTextEntity]
        public let media: [Media]
        public let target: Target
        public let messageId: MessageId?
        public let startParam: String?
        public let buttonText: String?
        public let sponsorInfo: String?
        public let additionalInfo: String?
        public let canReport: Bool

        public init(
            opaqueId: Data,
            messageType: MessageType,
            displayAvatar: Bool,
            text: String,
            textEntities: [MessageTextEntity],
            media: [Media],
            target: Target,
            messageId: MessageId?,
            startParam: String?,
            buttonText: String?,
            sponsorInfo: String?,
            additionalInfo: String?,
            canReport: Bool
        ) {
            self.opaqueId = opaqueId
            self.messageType = messageType
            self.displayAvatar = displayAvatar
            self.text = text
            self.textEntities = textEntities
            self.media = media
            self.target = target
            self.messageId = messageId
            self.startParam = startParam
            self.buttonText = buttonText
            self.sponsorInfo = sponsorInfo
            self.additionalInfo = additionalInfo
            self.canReport = canReport
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.opaqueId = try container.decode(Data.self, forKey: .opaqueId)
            
            if let messageType = try container.decodeIfPresent(Int32.self, forKey: .messageType) {
                self.messageType = MessageType(rawValue: messageType) ?? .sponsored
            } else {
                self.messageType = .sponsored
            }
            
            self.displayAvatar = try container.decodeIfPresent(Bool.self, forKey: .displayAvatar) ?? false
            
            self.text = try container.decode(String.self, forKey: .text)
            self.textEntities = try container.decode([MessageTextEntity].self, forKey: .textEntities)

            let mediaData = try container.decode([Data].self, forKey: .media)
            self.media = mediaData.compactMap { data -> Media? in
                return PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? Media
            }

            self.target = try container.decode(Target.self, forKey: .target)
            self.messageId = try container.decodeIfPresent(MessageId.self, forKey: .messageId)
            self.startParam = try container.decodeIfPresent(String.self, forKey: .startParam)
            self.buttonText = try container.decodeIfPresent(String.self, forKey: .buttonText)
            
            self.sponsorInfo = try container.decodeIfPresent(String.self, forKey: .sponsorInfo)
            self.additionalInfo = try container.decodeIfPresent(String.self, forKey: .additionalInfo)
            
            self.canReport = try container.decodeIfPresent(Bool.self, forKey: .displayAvatar) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(self.opaqueId, forKey: .opaqueId)
            try container.encode(self.messageType.rawValue, forKey: .messageType)
            try container.encode(self.displayAvatar, forKey: .displayAvatar)
            try container.encode(self.text, forKey: .text)
            try container.encode(self.textEntities, forKey: .textEntities)

            let mediaData = self.media.map { media -> Data in
                let encoder = PostboxEncoder()
                encoder.encodeRootObject(media)
                return encoder.makeData()
            }
            try container.encode(mediaData, forKey: .media)

            try container.encode(self.target, forKey: .target)
            try container.encodeIfPresent(self.messageId, forKey: .messageId)
            try container.encodeIfPresent(self.startParam, forKey: .startParam)
            try container.encodeIfPresent(self.buttonText, forKey: .buttonText)
            
            try container.encodeIfPresent(self.sponsorInfo, forKey: .sponsorInfo)
            try container.encodeIfPresent(self.additionalInfo, forKey: .additionalInfo)
            
            try container.encode(self.canReport, forKey: .canReport)
        }

        public static func ==(lhs: CachedMessage, rhs: CachedMessage) -> Bool {
            if lhs.opaqueId != rhs.opaqueId {
                return false
            }
            if lhs.messageType != rhs.messageType {
                return false
            }
            if lhs.text != rhs.text {
                return false
            }
            if lhs.textEntities != rhs.textEntities {
                return false
            }
            if lhs.media.count != rhs.media.count {
                return false
            }
            for i in 0 ..< lhs.media.count {
                if !lhs.media[i].isEqual(to: rhs.media[i]) {
                    return false
                }
            }
            if lhs.target != rhs.target {
                return false
            }
            if lhs.messageId != rhs.messageId {
                return false
            }
            if lhs.startParam != rhs.startParam {
                return false
            }
            if lhs.buttonText != rhs.buttonText {
                return false
            }
            if lhs.sponsorInfo != rhs.sponsorInfo {
                return false
            }
            if lhs.additionalInfo != rhs.additionalInfo {
                return false
            }
            if lhs.canReport != rhs.canReport {
                return false
            }
            return true
        }

        func toMessage(peerId: PeerId, transaction: Transaction) -> Message? {
            var attributes: [MessageAttribute] = []

            let target: AdMessageAttribute.MessageTarget
            switch self.target {
            case let .peer(peerId):
                target = .peer(id: peerId, message: self.messageId, startParam: self.startParam)
            case let .invite(invite):
                target = .join(title: invite.title, joinHash: invite.joinHash, peer: invite.peer.flatMap(EnginePeer.init))
            case let .webPage(webPage):
                target = .webPage(title: webPage.title, url: webPage.url)
            case let .botApp(peerId, botApp):
                target = .botApp(peerId: peerId, app: botApp, startParam: self.startParam)
            }
            let mappedMessageType: AdMessageAttribute.MessageType
            switch self.messageType {
            case .sponsored:
                mappedMessageType = .sponsored
            case .recommended:
                mappedMessageType = .recommended
            }
            attributes.append(AdMessageAttribute(opaqueId: self.opaqueId, messageType: mappedMessageType, displayAvatar: self.displayAvatar, target: target, buttonText: self.buttonText, sponsorInfo: self.sponsorInfo, additionalInfo: self.additionalInfo, canReport: self.canReport))
            if !self.textEntities.isEmpty {
                let attribute = TextEntitiesMessageAttribute(entities: self.textEntities)
                attributes.append(attribute)
            }

            var messagePeers = SimpleDictionary<PeerId, Peer>()

            if let peer = transaction.getPeer(peerId) {
                messagePeers[peer.id] = peer
            }
            
            let author: Peer
            switch self.target {
            case let .peer(peerId), let .botApp(peerId, _):
                if let peer = transaction.getPeer(peerId) {
                    author = peer
                } else {
                    return nil
                }
            case let .invite(invite):
                author = TelegramChannel(
                    id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1)),
                    accessHash: nil,
                    title: invite.title,
                    username: nil,
                    photo: [],
                    creationDate: 0,
                    version: 0,
                    participationStatus: .left,
                    info: .broadcast(TelegramChannelBroadcastInfo(flags: [])),
                    flags: [],
                    restrictionInfo: nil,
                    adminRights: nil,
                    bannedRights: nil,
                    defaultBannedRights: nil,
                    usernames: [],
                    storiesHidden: nil,
                    nameColor: invite.nameColor,
                    backgroundEmojiId: nil,
                    profileColor: nil,
                    profileBackgroundEmojiId: nil,
                    emojiStatus: nil,
                    approximateBoostLevel: nil
                )
            case let .webPage(webPage):
                author = TelegramChannel(
                    id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1)),
                    accessHash: nil,
                    title: webPage.title,
                    username: nil,
                    photo: webPage.photo?.representations ?? [],
                    creationDate: 0,
                    version: 0,
                    participationStatus: .left,
                    info: .broadcast(TelegramChannelBroadcastInfo(flags: [])),
                    flags: [],
                    restrictionInfo: nil,
                    adminRights: nil,
                    bannedRights: nil,
                    defaultBannedRights: nil,
                    usernames: [],
                    storiesHidden: nil,
                    nameColor: .blue,
                    backgroundEmojiId: nil,
                    profileColor: nil,
                    profileBackgroundEmojiId: nil,
                    emojiStatus: nil,
                    approximateBoostLevel: nil
                )
            }
            
            messagePeers[author.id] = author
            
            let messageHash = (self.text.hashValue &+ 31 &* peerId.hashValue) &* 31 &+ author.id.hashValue
            let messageStableVersion = UInt32(bitPattern: Int32(truncatingIfNeeded: messageHash))
            
            var media: [Media] = self.media
            if media.isEmpty, case let .invite(invite) = self.target, let image = invite.image {
                media.append(image)
            }

            return Message(
                stableId: 0,
                stableVersion: messageStableVersion,
                id: MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: 0),
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: Int32.max - 1,
                flags: [.Incoming],
                tags: [],
                globalTags: [],
                localTags: [],
                customTags: [],
                forwardInfo: nil,
                author: author,
                text: self.text,
                attributes: attributes,
                media: media,
                peers: messagePeers,
                associatedMessages: SimpleDictionary<MessageId, Message>(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
        }
    }

    private let queue: Queue
    private let account: Account
    private let peerId: PeerId

    private let maskAsSeenDisposables = DisposableDict<Data>()

    struct CachedState: Codable, PostboxCoding {
        enum CodingKeys: String, CodingKey {
            case timestamp
            case interPostInterval
            case messages
        }

        var timestamp: Int32
        var interPostInterval: Int32?
        var messages: [CachedMessage]

        init(timestamp: Int32, interPostInterval: Int32?, messages: [CachedMessage]) {
            self.timestamp = timestamp
            self.interPostInterval = interPostInterval
            self.messages = messages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.timestamp = try container.decode(Int32.self, forKey: .timestamp)
            self.interPostInterval = try container.decodeIfPresent(Int32.self, forKey: .interPostInterval)
            self.messages = try container.decode([CachedMessage].self, forKey: .messages)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(self.timestamp, forKey: .timestamp)
            try container.encodeIfPresent(self.interPostInterval, forKey: .interPostInterval)
            try container.encode(self.messages, forKey: .messages)
        }

        init(decoder: PostboxDecoder) {
            self.timestamp = decoder.decodeInt32ForKey("timestamp", orElse: 0)
            self.interPostInterval = decoder.decodeOptionalInt32ForKey("interPostInterval")
            if let messagesData = decoder.decodeOptionalDataArrayForKey("messages") {
                self.messages = messagesData.compactMap { data -> CachedMessage? in
                    return try? AdaptedPostboxDecoder().decode(CachedMessage.self, from: data)
                }
            } else {
                self.messages = []
            }
        }

        func encode(_ encoder: PostboxEncoder) {
            encoder.encodeInt32(self.timestamp, forKey: "timestamp")
            if let interPostInterval = self.interPostInterval {
                encoder.encodeInt32(interPostInterval, forKey: "interPostInterval")
            } else {
                encoder.encodeNil(forKey: "interPostInterval")
            }
            encoder.encodeDataArray(self.messages.compactMap { message -> Data? in
                return try? AdaptedPostboxEncoder().encode(message)
            }, forKey: "messages")
        }

        public static func getCached(postbox: Postbox, peerId: PeerId) -> Signal<CachedState?, NoError> {
            return postbox.transaction { transaction -> CachedState? in
                let key = ValueBoxKey(length: 8)
                key.setInt64(0, value: peerId.toInt64())
                if let entry = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedAdMessageStates, key: key))?.get(CachedState.self) {
                    return entry
                } else {
                    return nil
                }
            }
        }

        public static func setCached(transaction: Transaction, peerId: PeerId, state: CachedState?) {
            let key = ValueBoxKey(length: 8)
            key.setInt64(0, value: peerId.toInt64())
            let id = ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedAdMessageStates, key: key)
            if let state = state, let entry = CodableEntry(state) {
                transaction.putItemCacheEntry(id: id, entry: entry)
            } else {
                transaction.removeItemCacheEntry(id: id)
            }
        }
    }
    
    struct State: Equatable {
        var interPostInterval: Int32?
        var messages: [Message]

        static func ==(lhs: State, rhs: State) -> Bool {
            if lhs.interPostInterval != rhs.interPostInterval {
                return false
            }
            if lhs.messages.count != rhs.messages.count {
                return false
            }
            for i in 0 ..< lhs.messages.count {
                if lhs.messages[i].id != rhs.messages[i].id {
                    return false
                }
                if lhs.messages[i].stableId != rhs.messages[i].stableId {
                    return false
                }
            }
            return true
        }
    }
    
    let state = Promise<State>()
    private var stateValue: State? {
        didSet {
            if let stateValue = self.stateValue, stateValue != oldValue {
                self.state.set(.single(stateValue))
            }
        }
    }

    private let disposable = MetaDisposable()
    
    init(queue: Queue, account: Account, peerId: PeerId) {
        self.queue = queue
        self.account = account
        self.peerId = peerId
        
        let accountPeerId = account.peerId

        self.stateValue = State(interPostInterval: nil, messages: [])

        self.state.set(CachedState.getCached(postbox: account.postbox, peerId: peerId)
        |> mapToSignal { cachedState -> Signal<State, NoError> in
            if let cachedState = cachedState, cachedState.timestamp >= Int32(Date().timeIntervalSince1970) - 5 * 60 {
                return account.postbox.transaction { transaction -> State in
                    return State(interPostInterval: cachedState.interPostInterval, messages: cachedState.messages.compactMap { message -> Message? in
                        return message.toMessage(peerId: peerId, transaction: transaction)
                    })
                }
            } else {
                return .single(State(interPostInterval: nil, messages: []))
            }
        })

        let signal: Signal<(interPostInterval: Int32?, messages: [Message]), NoError> = account.postbox.transaction { transaction -> Api.InputChannel? in
            return transaction.getPeer(peerId).flatMap(apiInputChannel)
        }
        |> mapToSignal { inputChannel -> Signal<(interPostInterval: Int32?, messages: [Message]), NoError> in
            guard let inputChannel = inputChannel else {
                return .single((nil, []))
            }
            return account.network.request(Api.functions.channels.getSponsoredMessages(channel: inputChannel))
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.messages.SponsoredMessages?, NoError> in
                return .single(nil)
            }
            |> mapToSignal { result -> Signal<(interPostInterval: Int32?, messages: [Message]), NoError> in
                guard let result = result else {
                    return .single((nil, []))
                }

                return account.postbox.transaction { transaction -> (interPostInterval: Int32?, messages: [Message]) in
                    switch result {
                    case let .sponsoredMessages(_, postsBetween, messages, chats, users):
                        let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)

                        var parsedMessages: [CachedMessage] = []

                        for message in messages {
                            switch message {
                            case let .sponsoredMessage(flags, randomId, fromId, chatInvite, chatInviteHash, channelPost, startParam, webPage, botApp, message, entities, buttonText, sponsorInfo, additionalInfo):
                                var parsedEntities: [MessageTextEntity] = []
                                if let entities = entities {
                                    parsedEntities = messageTextEntitiesFromApiEntities(entities)
                                }
                                
                                let isRecommended = (flags & (1 << 5)) != 0
                                var displayAvatar = (flags & (1 << 6)) != 0
                                let canReport = (flags & (1 << 12)) != 0
                                
                                var target: CachedMessage.Target?
                                if let fromId = fromId {
                                    if let botApp = botApp, let app = BotApp(apiBotApp: botApp) {
                                        target = .botApp(fromId.peerId, app)
                                    } else {
                                        target = .peer(fromId.peerId)
                                    }
                                } else if let webPage = webPage {
                                    switch webPage {
                                    case let .sponsoredWebPage(_, url, siteName, photo):
                                        let photo = photo.flatMap { telegramMediaImageFromApiPhoto($0) }
                                        target = .webPage(CachedMessage.Target.WebPage(title: siteName, url: url, photo: photo))
                                    }
                                } else if let chatInvite = chatInvite, let chatInviteHash = chatInviteHash {
                                    switch chatInvite {
                                    case let .chatInvite(flags, title, _, photo, participantsCount, participants, nameColor):
                                        let image = telegramMediaImageFromApiPhoto(photo)
                                        let flags: ExternalJoiningChatState.Invite.Flags = .init(isChannel: (flags & (1 << 0)) != 0, isBroadcast: (flags & (1 << 1)) != 0, isPublic: (flags & (1 << 2)) != 0, isMegagroup: (flags & (1 << 3)) != 0, requestNeeded: (flags & (1 << 6)) != 0, isVerified: (flags & (1 << 7)) != 0, isScam: (flags & (1 << 8)) != 0, isFake: (flags & (1 << 9)) != 0)
                                        
                                        let _ = flags
                                        let _ = participantsCount
                                        let _ = participants
                                        
                                        target = .invite(CachedMessage.Target.Invite(
                                            title: title,
                                            joinHash: chatInviteHash,
                                            nameColor: PeerNameColor(rawValue: nameColor),
                                            image: displayAvatar ? image : nil,
                                            peer: nil
                                        ))
                                        
                                        displayAvatar = false
                                    case let .chatInvitePeek(chat, _):
                                        if let peer = parseTelegramGroupOrChannel(chat: chat) {
                                            target = .invite(CachedMessage.Target.Invite(
                                                title: peer.debugDisplayTitle,
                                                joinHash: chatInviteHash,
                                                nameColor: peer.nameColor,
                                                image: nil,
                                                peer: displayAvatar ? peer : nil
                                            ))
                                        }
                                        
                                        displayAvatar = false
                                    case let .chatInviteAlready(chat):
                                        if let peer = parseTelegramGroupOrChannel(chat: chat) {
                                            target = .invite(CachedMessage.Target.Invite(
                                                title: peer.debugDisplayTitle,
                                                joinHash: chatInviteHash,
                                                nameColor: peer.nameColor,
                                                image: nil,
                                                peer: displayAvatar ? peer : nil
                                            ))
                                        }
                                        
                                        displayAvatar = false
                                    }
                                } 
//                                else if let botApp = app.flatMap({ BotApp(apiBotApp: $0) }) {
//                                    target = .botApp(botApp)
//                                }
                                
                                var messageId: MessageId?
                                if let fromId = fromId, let channelPost = channelPost {
                                    messageId = MessageId(peerId: fromId.peerId, namespace: Namespaces.Message.Cloud, id: channelPost)
                                }

                                if let target = target {
                                    parsedMessages.append(CachedMessage(
                                        opaqueId: randomId.makeData(),
                                        messageType: isRecommended ? .recommended : .sponsored,
                                        displayAvatar: displayAvatar,
                                        text: message,
                                        textEntities: parsedEntities,
                                        media: [],
                                        target: target,
                                        messageId: messageId,
                                        startParam: startParam,
                                        buttonText: buttonText,
                                        sponsorInfo: sponsorInfo,
                                        additionalInfo: additionalInfo,
                                        canReport: canReport
                                    ))
                                }
                            }
                        }

                        CachedState.setCached(transaction: transaction, peerId: peerId, state: CachedState(timestamp: Int32(Date().timeIntervalSince1970), interPostInterval: postsBetween, messages: parsedMessages))

                        return (postsBetween, parsedMessages.compactMap { message -> Message? in
                            return message.toMessage(peerId: peerId, transaction: transaction)
                        })
                    case .sponsoredMessagesEmpty:
                        return (nil, [])
                    }
                }
            }
        }
        
        self.disposable.set((signal
        |> deliverOn(self.queue)).start(next: { [weak self] interPostInterval, messages in
            guard let strongSelf = self else {
                return
            }
            strongSelf.stateValue = State(interPostInterval: interPostInterval, messages: messages)
        }))
    }
    
    deinit {
        self.disposable.dispose()
        self.maskAsSeenDisposables.dispose()
    }

    func markAsSeen(opaqueId: Data) {
        let signal: Signal<Never, NoError> = account.postbox.transaction { transaction -> Api.InputChannel? in
            return transaction.getPeer(self.peerId).flatMap(apiInputChannel)
        }
        |> mapToSignal { inputChannel -> Signal<Never, NoError> in
            guard let inputChannel = inputChannel else {
                return .complete()
            }
            return self.account.network.request(Api.functions.channels.viewSponsoredMessage(channel: inputChannel, randomId: Buffer(data: opaqueId)))
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .single(.boolFalse)
            }
            |> ignoreValues
        }
        self.maskAsSeenDisposables.set(signal.start(), forKey: opaqueId)
    }
    
    func markAction(opaqueId: Data) {
        let account = self.account
        let signal: Signal<Never, NoError> = account.postbox.transaction { transaction -> Api.InputChannel? in
            return transaction.getPeer(self.peerId).flatMap(apiInputChannel)
        }
        |> mapToSignal { inputChannel -> Signal<Never, NoError> in
            guard let inputChannel = inputChannel else {
                return .complete()
            }
            return account.network.request(Api.functions.channels.clickSponsoredMessage(channel: inputChannel, randomId: Buffer(data: opaqueId)))
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .single(.boolFalse)
            }
            |> ignoreValues
        }
        let _ = signal.start()
    }
    
    func remove(opaqueId: Data) {
        if var stateValue = self.stateValue {
            if let index = stateValue.messages.firstIndex(where: { $0.adAttribute?.opaqueId == opaqueId }) {
                stateValue.messages.remove(at: index)
                self.stateValue = stateValue
            }
        }
        
        let peerId = self.peerId
        let _ = (self.account.postbox.transaction { transaction -> Void in
            let key = ValueBoxKey(length: 8)
            key.setInt64(0, value: peerId.toInt64())
            let id = ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedAdMessageStates, key: key)
            guard var cachedState = transaction.retrieveItemCacheEntry(id: id)?.get(CachedState.self) else {
                return
            }
            if let index = cachedState.messages.firstIndex(where: { $0.opaqueId == opaqueId }) {
                cachedState.messages.remove(at: index)
                if let entry = CodableEntry(cachedState) {
                    transaction.putItemCacheEntry(id: id, entry: entry)
                }
            }
        }).start()
    }
}

public class AdMessagesHistoryContext {
    private let queue = Queue()
    private let impl: QueueLocalObject<AdMessagesHistoryContextImpl>
    
    public var state: Signal<(interPostInterval: Int32?, messages: [Message]), NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            
            self.impl.with { impl in
                let stateDisposable = impl.state.get().start(next: { state in
                    subscriber.putNext((state.interPostInterval, state.messages))
                })
                disposable.set(stateDisposable)
            }
            
            return disposable
        }
    }
    
    public init(account: Account, peerId: PeerId) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return AdMessagesHistoryContextImpl(queue: queue, account: account, peerId: peerId)
        })
    }

    public func markAsSeen(opaqueId: Data) {
        self.impl.with { impl in
            impl.markAsSeen(opaqueId: opaqueId)
        }
    }
    
    public func markAction(opaqueId: Data) {
        self.impl.with { impl in
            impl.markAction(opaqueId: opaqueId)
        }
    }
    
    public func remove(opaqueId: Data) {
        self.impl.with { impl in
            impl.remove(opaqueId: opaqueId)
        }
    }
}
