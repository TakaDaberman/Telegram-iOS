import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi


public enum UploadStickerStatus {
    case progress(Float)
    case complete(CloudDocumentMediaResource, String)
}

public enum UploadStickerError {
    case generic
}

private struct UploadedStickerData {
    fileprivate let resource: MediaResource
    fileprivate let content: UploadedStickerDataContent
}

private enum UploadedStickerDataContent {
    case result(MultipartUploadResult)
    case error
}

private func uploadedSticker(postbox: Postbox, network: Network, resource: MediaResource) -> Signal<UploadedStickerData, NoError> {
    return multipartUpload(network: network, postbox: postbox, source: .resource(.standalone(resource: resource)), encrypt: false, tag: TelegramMediaResourceFetchTag(statsCategory: .stickers, userContentType: .sticker), hintFileSize: nil, hintFileIsLarge: false, forceNoBigParts: false)
    |> map { result -> UploadedStickerData in
        return UploadedStickerData(resource: resource, content: .result(result))
    }
    |> `catch` { _ -> Signal<UploadedStickerData, NoError> in
        return .single(UploadedStickerData(resource: resource, content: .error))
    }
}

func _internal_uploadSticker(account: Account, peer: Peer, resource: MediaResource, alt: String, dimensions: PixelDimensions, mimeType: String) -> Signal<UploadStickerStatus, UploadStickerError> {
    guard let inputPeer = apiInputPeer(peer) else {
        return .fail(.generic)
    }
    return uploadedSticker(postbox: account.postbox, network: account.network, resource: resource)
    |> mapError { _ -> UploadStickerError in }
    |> mapToSignal { result -> Signal<UploadStickerStatus, UploadStickerError> in
        switch result.content {
            case .error:
                return .fail(.generic)
            case let .result(resultData):
                switch resultData {
                    case let .progress(progress):
                        return .single(.progress(progress))
                    case let .inputFile(file):
                        let flags: Int32 = 0
                        var attributes: [Api.DocumentAttribute] = []
                        attributes.append(.documentAttributeSticker(flags: 0, alt: alt, stickerset: .inputStickerSetEmpty, maskCoords: nil))
                        attributes.append(.documentAttributeImageSize(w: dimensions.width, h: dimensions.height))
                        return account.network.request(Api.functions.messages.uploadMedia(flags: 0, businessConnectionId: nil, peer: inputPeer, media: Api.InputMedia.inputMediaUploadedDocument(flags: flags, file: file, thumb: nil, mimeType: mimeType, attributes: attributes, stickers: nil, ttlSeconds: nil)))
                        |> mapError { _ -> UploadStickerError in return .generic }
                        |> mapToSignal { media -> Signal<UploadStickerStatus, UploadStickerError> in
                            switch media {
                                case let .messageMediaDocument(_, document, _, _):
                                    if let document = document, let file = telegramMediaFileFromApiDocument(document), let resource = file.resource as? CloudDocumentMediaResource {
                                        return .single(.complete(resource, file.mimeType))
                                    }
                                default:
                                    break
                            }
                            return .fail(.generic)
                        }
                    default:
                        return .fail(.generic)
                }
        }
    }
}

public enum CreateStickerSetError {
    case generic
}

public struct ImportSticker {
    public let resource: MediaResource
    let emojis: [String]
    public let dimensions: PixelDimensions
    public let mimeType: String
    public let keywords: String
    
    public init(resource: MediaResource, emojis: [String], dimensions: PixelDimensions, mimeType: String, keywords: String) {
        self.resource = resource
        self.emojis = emojis
        self.dimensions = dimensions
        self.mimeType = mimeType
        self.keywords = keywords
    }
}

public extension ImportSticker {
    var stickerPackItem: StickerPackItem? {
        guard let resource = self.resource as? TelegramMediaResource else {
            return nil
        }
        var fileAttributes: [TelegramMediaFileAttribute] = []
        if self.mimeType == "video/webm" {
            fileAttributes.append(.FileName(fileName: "sticker.webm"))
            fileAttributes.append(.Animated)
            fileAttributes.append(.Sticker(displayText: "", packReference: nil, maskData: nil))
        } else if self.mimeType == "application/x-tgsticker" {
            fileAttributes.append(.FileName(fileName: "sticker.tgs"))
            fileAttributes.append(.Animated)
            fileAttributes.append(.Sticker(displayText: "", packReference: nil, maskData: nil))
        } else {
            fileAttributes.append(.FileName(fileName: "sticker.webp"))
        }
        fileAttributes.append(.ImageSize(size: self.dimensions))
        return StickerPackItem(index: ItemCollectionItemIndex(index: 0, id: 0), file: TelegramMediaFile(fileId: EngineMedia.Id(namespace: 0, id: 0), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: self.mimeType, size: nil, attributes: fileAttributes), indexKeys: [])
    }
}

public enum CreateStickerSetStatus {
    case progress(Float, Int32, Int32)
    case complete(StickerPackCollectionInfo, [StickerPackItem])
}

public enum CreateStickerSetType {
    public enum ContentType {
        case image
        case animation
        case video
    }
    
    case stickers(content: ContentType)
    case emoji(content: ContentType, textColored: Bool)
    
    var contentType: ContentType {
        switch self {
        case let .stickers(content), let .emoji(content, _):
            return content
        }
    }
}

func _internal_createStickerSet(account: Account, title: String, shortName: String, stickers: [ImportSticker], thumbnail: ImportSticker?, type: CreateStickerSetType, software: String?) -> Signal<CreateStickerSetStatus, CreateStickerSetError> {
    return account.postbox.loadedPeerWithId(account.peerId)
    |> castError(CreateStickerSetError.self)
    |> mapToSignal { peer -> Signal<CreateStickerSetStatus, CreateStickerSetError> in
        guard let inputUser = apiInputUser(peer) else {
            return .fail(.generic)
        }
        var uploadStickers: [Signal<UploadStickerStatus, CreateStickerSetError>] = []
        var stickers = stickers
        if let thumbnail = thumbnail {
            stickers.append(thumbnail)
        }
        for sticker in stickers {
            if let resource = sticker.resource as? CloudDocumentMediaResource {
                uploadStickers.append(.single(.complete(resource, sticker.mimeType)))
            } else {
                uploadStickers.append(_internal_uploadSticker(account: account, peer: peer, resource: sticker.resource, alt: sticker.emojis.first ?? "", dimensions: sticker.dimensions, mimeType: sticker.mimeType)
                |> mapError { _ -> CreateStickerSetError in
                    return .generic
                })
            }
        }
        return combineLatest(uploadStickers)
        |> mapToSignal { uploadedStickers -> Signal<CreateStickerSetStatus, CreateStickerSetError> in
            var resources: [CloudDocumentMediaResource] = []
            for sticker in uploadedStickers {
                if case let .complete(resource, _) = sticker {
                    resources.append(resource)
                }
            }
            if resources.count == stickers.count {
                var flags: Int32 = 0
                switch type.contentType {
                    case .animation:
                        flags |= (1 << 1)
                    case .video:
                        flags |= (1 << 4)
                    default:
                        break
                }
                if case let .emoji(_, textColored) = type {
                    flags |= (1 << 5)
                    if textColored {
                        flags |= (1 << 6)
                    }
                }
                var inputStickers: [Api.InputStickerSetItem] = []
                let stickerDocuments = thumbnail != nil ? resources.dropLast() : resources
                for i in 0 ..< stickerDocuments.count {
                    let sticker = stickers[i]
                    let resource = resources[i]
                    
                    var flags: Int32 = 0
                    if sticker.keywords.count > 0 {
                        flags |= (1 << 1)
                    }
                    
                    inputStickers.append(.inputStickerSetItem(flags: flags, document: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference ?? Data())), emoji: sticker.emojis.joined(), maskCoords: nil, keywords: sticker.keywords))
                }
                var thumbnailDocument: Api.InputDocument?
                if thumbnail != nil, let resource = resources.last {
                    flags |= (1 << 2)
                    thumbnailDocument = .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference ?? Data()))
                }
                if let software = software, !software.isEmpty {
                    flags |= (1 << 3)
                }
                return account.network.request(Api.functions.stickers.createStickerSet(flags: flags, userId: inputUser, title: title, shortName: shortName, thumb: thumbnailDocument, stickers: inputStickers, software: software))
                |> mapError { error -> CreateStickerSetError in
                    return .generic
                }
                |> mapToSignal { result -> Signal<CreateStickerSetStatus, CreateStickerSetError> in
                    guard let (info, items) = parseStickerSetInfoAndItems(apiStickerSet: result) else {
                        return .complete()
                    }
                    return .single(.complete(info, items))
                }
            } else {
                var totalProgress: Float = 0.0
                var completeCount: Int32 = 0
                for sticker in uploadedStickers {
                    switch sticker {
                        case .complete:
                            totalProgress += 1.0
                            completeCount += 1
                        case let .progress(progress):
                            totalProgress += progress
                            if progress == 1.0 {
                                completeCount += 1
                            }
                    }
                }
                let normalizedProgress = min(1.0, max(0.0, totalProgress / Float(stickers.count)))
                return .single(.progress(normalizedProgress, completeCount, Int32(uploadedStickers.count)))
            }
        }
    }
}

public enum RenameStickerSetError {
    case generic
}

func _internal_renameStickerSet(account: Account, packReference: StickerPackReference, title: String) -> Signal<Never, RenameStickerSetError> {
    return account.network.request(Api.functions.stickers.renameStickerSet(stickerset: packReference.apiInputStickerSet, title: title))
    |> mapError { error -> RenameStickerSetError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, RenameStickerSetError> in
        guard let (info, items) = parseStickerSetInfoAndItems(apiStickerSet: result) else {
            return .complete()
        }
        return account.postbox.transaction { transaction -> Void in
            let collectionNamespace = Namespaces.ItemCollection.CloudStickerPacks
            var currentInfos = transaction.getItemCollectionsInfos(namespace: collectionNamespace).map { $0.1 as! StickerPackCollectionInfo }
            if let index = currentInfos.firstIndex(where: { $0.id == info.id }) {
                currentInfos[index] = info
            }
            transaction.replaceItemCollectionInfos(namespace: collectionNamespace, itemCollectionInfos: currentInfos.map { ($0.id, $0) })
            cacheStickerPack(transaction: transaction, info: info, items: items)
        }
        |> castError(RenameStickerSetError.self)
        |> ignoreValues
    }
}

public enum DeleteStickerSetError {
    case generic
}

func _internal_deleteStickerSet(account: Account, packReference: StickerPackReference) -> Signal<Never, DeleteStickerSetError> {
    return account.network.request(Api.functions.stickers.deleteStickerSet(stickerset: packReference.apiInputStickerSet))
    |> mapError { error -> DeleteStickerSetError in
        return .generic
    }
    |> mapToSignal { _ in
        return account.postbox.transaction { transaction in
            if let (info, _, _) = cachedStickerPack(transaction: transaction, reference: packReference) {
                transaction.removeItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedStickerPacks, key: CachedStickerPack.cacheKey(info.id)))
                transaction.removeItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedStickerPacks, key: CachedStickerPack.cacheKey(shortName: info.shortName.lowercased())))
            }
            
            if case let .id(id, _) = packReference {
                transaction.removeItemCollection(collectionId: ItemCollectionId(namespace: Namespaces.ItemCollection.CloudStickerPacks, id: id))
            }
        }
        |> castError(DeleteStickerSetError.self)
    }
    |> ignoreValues
}

public enum AddStickerToSetError {
    case generic
}

func _internal_addStickerToStickerSet(account: Account, packReference: StickerPackReference, sticker: ImportSticker) -> Signal<Bool, AddStickerToSetError> {
    let uploadSticker: Signal<UploadStickerStatus, AddStickerToSetError>
    if let resource = sticker.resource as? CloudDocumentMediaResource {
        uploadSticker = .single(.complete(resource, sticker.mimeType))
    } else {
        uploadSticker = account.postbox.loadedPeerWithId(account.peerId)
        |> castError(AddStickerToSetError.self)
        |> mapToSignal { peer in
            return _internal_uploadSticker(account: account, peer: peer, resource: sticker.resource, alt: sticker.emojis.first ?? "", dimensions: sticker.dimensions, mimeType: sticker.mimeType)
            |> mapError { _ -> AddStickerToSetError in
                return .generic
            }
        }
    }
    return uploadSticker
    |> mapToSignal { uploadedSticker in
        guard case let .complete(resource, _) = uploadedSticker else {
            return .complete()
        }
        
        var flags: Int32 = 0
        if sticker.keywords.count > 0 {
            flags |= (1 << 1)
        }
        let inputSticker: Api.InputStickerSetItem = .inputStickerSetItem(flags: flags, document: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference ?? Data())), emoji: sticker.emojis.joined(), maskCoords: nil, keywords: sticker.keywords)
       
        return account.network.request(Api.functions.stickers.addStickerToSet(stickerset: packReference.apiInputStickerSet, sticker: inputSticker))
        |> mapError { error -> AddStickerToSetError in
            return .generic
        }
        |> mapToSignal { result -> Signal<Bool, AddStickerToSetError> in
            guard let (info, items) = parseStickerSetInfoAndItems(apiStickerSet: result) else {
                return .complete()
            }
            return account.postbox.transaction { transaction -> Bool in
                if transaction.getItemCollectionInfo(collectionId: info.id) != nil {
                    transaction.replaceItemCollectionItems(collectionId: info.id, items: items)
                }
                cacheStickerPack(transaction: transaction, info: info, items: items)
                return true
            }
            |> castError(AddStickerToSetError.self)
        }
    }
}

public enum ReorderStickerError {
    case generic
}

func _internal_reorderSticker(account: Account, sticker: FileMediaReference, position: Int) -> Signal<Never, ReorderStickerError> {
    guard let resource = sticker.media.resource as? CloudDocumentMediaResource else {
        return .fail(.generic)
    }
    return account.network.request(Api.functions.stickers.changeStickerPosition(sticker: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference)), position: Int32(position)))
    |> mapError { error -> ReorderStickerError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, ReorderStickerError> in
        guard let (info, items) = parseStickerSetInfoAndItems(apiStickerSet: result) else {
            return .complete()
        }
        return account.postbox.transaction { transaction -> Void in
            if transaction.getItemCollectionInfo(collectionId: info.id) != nil {
                transaction.replaceItemCollectionItems(collectionId: info.id, items: items)
            }
            cacheStickerPack(transaction: transaction, info: info, items: items)
        }
        |> castError(ReorderStickerError.self)
        |> ignoreValues
    }
}


public enum DeleteStickerError {
    case generic
}

func _internal_deleteStickerFromStickerSet(account: Account, sticker: FileMediaReference) -> Signal<Never, DeleteStickerError> {
    guard let resource = sticker.media.resource as? CloudDocumentMediaResource else {
        return .fail(.generic)
    }
    return account.network.request(Api.functions.stickers.removeStickerFromSet(sticker: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference))))
    |> mapError { error -> DeleteStickerError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, DeleteStickerError> in
        guard let (info, items) = parseStickerSetInfoAndItems(apiStickerSet: result) else {
            return .complete()
        }
        return account.postbox.transaction { transaction -> Void in
            if transaction.getItemCollectionInfo(collectionId: info.id) != nil {
                transaction.replaceItemCollectionItems(collectionId: info.id, items: items)
            }
            cacheStickerPack(transaction: transaction, info: info, items: items)
        }
        |> castError(DeleteStickerError.self)
        |> ignoreValues
    }
}

public enum ReplaceStickerError {
    case generic
}

func _internal_replaceSticker(account: Account, previousSticker: FileMediaReference, sticker: ImportSticker) -> Signal<Never, ReplaceStickerError> {
    guard let previousResource = previousSticker.media.resource as? CloudDocumentMediaResource else {
        return .fail(.generic)
    }
    
    let uploadSticker: Signal<UploadStickerStatus, ReplaceStickerError>
    if let resource = sticker.resource as? CloudDocumentMediaResource {
        uploadSticker = .single(.complete(resource, sticker.mimeType))
    } else {
        uploadSticker = account.postbox.loadedPeerWithId(account.peerId)
        |> castError(ReplaceStickerError.self)
        |> mapToSignal { peer in
            return _internal_uploadSticker(account: account, peer: peer, resource: sticker.resource, alt: sticker.emojis.first ?? "", dimensions: sticker.dimensions, mimeType: sticker.mimeType)
            |> mapError { _ -> ReplaceStickerError in
                return .generic
            }
        }
    }
    return uploadSticker
    |> mapToSignal { uploadedSticker in
        guard case let .complete(resource, _) = uploadedSticker else {
            return .complete()
        }
        
        var flags: Int32 = 0
        if sticker.keywords.count > 0 {
            flags |= (1 << 1)
        }
        let inputSticker: Api.InputStickerSetItem = .inputStickerSetItem(flags: flags, document: .inputDocument(id: resource.fileId, accessHash: resource.accessHash, fileReference: Buffer(data: resource.fileReference ?? Data())), emoji: sticker.emojis.joined(), maskCoords: nil, keywords: sticker.keywords)
       
        return account.network.request(Api.functions.stickers.replaceSticker(sticker: .inputDocument(id: previousResource.fileId, accessHash: previousResource.accessHash, fileReference: Buffer(data: previousResource.fileReference ?? Data())), newSticker: inputSticker))
        |> mapError { error -> ReplaceStickerError in
            return .generic
        }
        |> mapToSignal { result -> Signal<Never, ReplaceStickerError> in
            guard let (info, items) = parseStickerSetInfoAndItems(apiStickerSet: result) else {
                return .complete()
            }
            return account.postbox.transaction { transaction -> Void in
                if transaction.getItemCollectionInfo(collectionId: info.id) != nil {
                    transaction.replaceItemCollectionItems(collectionId: info.id, items: items)
                }
                cacheStickerPack(transaction: transaction, info: info, items: items)
            }
            |> castError(ReplaceStickerError.self)
            |> ignoreValues
        }
    }
}

func _internal_getMyStickerSets(account: Account) -> Signal<[(StickerPackCollectionInfo, StickerPackItem?)], NoError> {
    return account.network.request(Api.functions.messages.getMyStickers(offsetId: 0, limit: 100))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.messages.MyStickers?, NoError> in
        return .single(nil)
    }
    |> map { result -> [(StickerPackCollectionInfo, StickerPackItem?)] in
        guard let result else {
            return []
        }
        var infos: [(StickerPackCollectionInfo, StickerPackItem?)] = []
        switch result {
        case let .myStickers(_, sets):
            for set in sets {
                switch set {
                case let .stickerSetCovered(set, cover):
                    let namespace: ItemCollectionId.Namespace
                    switch set {
                        case let .stickerSet(flags, _, _, _, _, _, _, _, _, _, _, _):
                            if (flags & (1 << 3)) != 0 {
                                namespace = Namespaces.ItemCollection.CloudMaskPacks
                            } else if (flags & (1 << 7)) != 0 {
                                namespace = Namespaces.ItemCollection.CloudEmojiPacks
                            } else {
                                namespace = Namespaces.ItemCollection.CloudStickerPacks
                            }
                    }
                    let info = StickerPackCollectionInfo(apiSet: set, namespace: namespace)
                    var firstItem: StickerPackItem?
                    if let file = telegramMediaFileFromApiDocument(cover), let id = file.id {
                        firstItem = StickerPackItem(index: ItemCollectionItemIndex(index: 0, id: id.id), file: file, indexKeys: [])
                    }
                    infos.append((info, firstItem))
                case let .stickerSetFullCovered(set, _, _, documents):
                    let namespace: ItemCollectionId.Namespace
                    switch set {
                        case let .stickerSet(flags, _, _, _, _, _, _, _, _, _, _, _):
                            if (flags & (1 << 3)) != 0 {
                                namespace = Namespaces.ItemCollection.CloudMaskPacks
                            } else if (flags & (1 << 7)) != 0 {
                                namespace = Namespaces.ItemCollection.CloudEmojiPacks
                            } else {
                                namespace = Namespaces.ItemCollection.CloudStickerPacks
                            }
                    }
                    let info = StickerPackCollectionInfo(apiSet: set, namespace: namespace)
                    var firstItem: StickerPackItem?
                    if let apiDocument = documents.first {
                        if let file = telegramMediaFileFromApiDocument(apiDocument), let id = file.id {
                            firstItem = StickerPackItem(index: ItemCollectionItemIndex(index: 0, id: id.id), file: file, indexKeys: [])
                        }
                    }
                    infos.append((info, firstItem))
                default:
                    break
                }
            }
        }
        return infos
    }
}

private func parseStickerSetInfoAndItems(apiStickerSet: Api.messages.StickerSet) -> (StickerPackCollectionInfo, [StickerPackItem])? {
    switch apiStickerSet {
    case .stickerSetNotModified:
        return nil
    case let .stickerSet(set, packs, keywords, documents):
        let namespace: ItemCollectionId.Namespace
        switch set {
            case let .stickerSet(flags, _, _, _, _, _, _, _, _, _, _, _):
                if (flags & (1 << 3)) != 0 {
                    namespace = Namespaces.ItemCollection.CloudMaskPacks
                } else if (flags & (1 << 7)) != 0 {
                    namespace = Namespaces.ItemCollection.CloudEmojiPacks
                } else {
                    namespace = Namespaces.ItemCollection.CloudStickerPacks
                }
        }
        let info = StickerPackCollectionInfo(apiSet: set, namespace: namespace)
        var indexKeysByFile: [MediaId: [MemoryBuffer]] = [:]
        for pack in packs {
            switch pack {
                case let .stickerPack(text, fileIds):
                    let key = ValueBoxKey(text).toMemoryBuffer()
                    for fileId in fileIds {
                        let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                        if indexKeysByFile[mediaId] == nil {
                            indexKeysByFile[mediaId] = [key]
                        } else {
                            indexKeysByFile[mediaId]!.append(key)
                        }
                    }
            }
        }
        for keyword in keywords {
            switch keyword {
            case let .stickerKeyword(documentId, texts):
                for text in texts {
                    let key = ValueBoxKey(text).toMemoryBuffer()
                    let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: documentId)
                    if indexKeysByFile[mediaId] == nil {
                        indexKeysByFile[mediaId] = [key]
                    } else {
                        indexKeysByFile[mediaId]!.append(key)
                    }
                }
            }
        }
        
        var items: [StickerPackItem] = []
        for apiDocument in documents {
            if let file = telegramMediaFileFromApiDocument(apiDocument), let id = file.id {
                let fileIndexKeys: [MemoryBuffer]
                if let indexKeys = indexKeysByFile[id] {
                    fileIndexKeys = indexKeys
                } else {
                    fileIndexKeys = []
                }
                items.append(StickerPackItem(index: ItemCollectionItemIndex(index: Int32(items.count), id: id.id), file: file, indexKeys: fileIndexKeys))
            }
        }
        return (info, items)
    }
}

func _internal_getStickerSetShortNameSuggestion(account: Account, title: String) -> Signal<String?, NoError> {
    return account.network.request(Api.functions.stickers.suggestShortName(title: title))
    |> map (Optional.init)
    |> `catch` { _ in
        return .single(nil)
    }
    |> map { result in
        guard let result = result else {
            return nil
        }
        switch result {
            case let .suggestedShortName(shortName):
                return shortName
        }
    }
}

func _internal_stickerSetShortNameAvailability(account: Account, shortName: String) -> Signal<AddressNameAvailability, NoError> {
    return account.network.request(Api.functions.stickers.checkShortName(shortName: shortName))
    |> map { result -> AddressNameAvailability in
        switch result {
            case .boolTrue:
                return .available
            case .boolFalse:
                return .taken
        }
    }
    |> `catch` { error -> Signal<AddressNameAvailability, NoError> in
        if error.errorDescription == "SHORT_NAME_OCCUPIED" {
            return .single(.taken)
        }
        return .single(.invalid)
    }
}
