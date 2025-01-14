//
//  CarPlayManager.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 8/12/19.
//  Copyright © 2019 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import MediaPlayer
import UIKit

enum BookPlayerError: Error {
  case UnableToLoadBooks(String)
}

enum IndexGuide {
  case tab

  var recentlyPlayed: Int {
    return 1
  }

  case library
  case folder

  var count: Int {
    switch self {
    case .tab:
      return 1
    case .library:
      return 2
    case .folder:
      return 3
    }
  }

  var content: Int {
    switch self {
    case .tab:
      return 0
    case .library:
      return 1
    case .folder:
      return 2
    }
  }
}

final class CarPlayManager: NSObject, MPPlayableContentDataSource, MPPlayableContentDelegate {
  static let shared = CarPlayManager()

  var library: Library?

  typealias Tab = (identifier: String, title: String, imageName: String)
  let tabs: [Tab] = [("tab-library", "library_title".localized, "carplayLibrary"),
                     ("tab-recent", "carplay_recent_title".localized, "carplayRecent")]

  private override init() {
    guard let library = try? DataManager.getLibrary() else { return }

    self.library = library
  }

  func createTabItem(for indexPath: IndexPath) -> MPContentItem {
    let tab = self.tabs[indexPath[IndexGuide.tab.content]]
    let item = MPContentItem(identifier: tab.identifier)
    item.title = tab.title
    item.isContainer = true
    item.isPlayable = false
    if let tabImage = UIImage(named: tab.imageName) {
      item.artwork = MPMediaItemArtwork(boundsSize: tabImage.size, requestHandler: { _ -> UIImage in
        tabImage
      })
    }

    return item
  }

  func numberOfChildItems(at indexPath: IndexPath) -> Int {
    if indexPath.indices.isEmpty {
      return 2
    }

    var mutableIndexPath = indexPath
    let sourceIndex = mutableIndexPath.removeFirst()

    guard let items = self.getSourceItems(for: sourceIndex) else {
      return 0
    }

    if mutableIndexPath.isEmpty {
      return items.count
    }

    let item = self.getItem(from: items, and: mutableIndexPath)

    guard let folder = item as? Folder,
          let count = folder.items?.count else {
      return 0
    }

    return count
  }

  func contentItem(at indexPath: IndexPath) -> MPContentItem? {
    // Populate tabs
    if indexPath.indices.count == IndexGuide.tab.count {
      return self.createTabItem(for: indexPath)
    }

    var mutableIndexPath = indexPath
    let sourceIndex = mutableIndexPath.removeFirst()

    // Fetch item
    guard let items = self.getSourceItems(for: sourceIndex) else {
      return nil
    }

    let libraryItem = self.getItem(from: items, and: mutableIndexPath)

    // Folders identifiers weren't unique, this is a quick fix
    if libraryItem.identifier == libraryItem.title {
      libraryItem.identifier = "\(libraryItem.title!)\(Date().timeIntervalSince1970)"
    }

    let item = MPContentItem(identifier: libraryItem.identifier)
    item.title = libraryItem.title

    item.playbackProgress = Float(libraryItem.progressPercentage)
    if let artwork = libraryItem.getArtwork(for: ThemeManager.shared.currentTheme) {
      item.artwork = MPMediaItemArtwork(boundsSize: artwork.size,
                                        requestHandler: { (_) -> UIImage in
                                          artwork
                                        })
    }

    if let book = libraryItem as? Book {
      item.subtitle = book.author
      item.isContainer = false
      item.isPlayable = true
    } else if let folder = libraryItem as? Folder {
      item.subtitle = folder.info()
      item.isContainer = indexPath[0] != IndexGuide.tab.recentlyPlayed
      item.isPlayable = indexPath[0] == IndexGuide.tab.recentlyPlayed
    }

    return item
  }

  func playableContentManager(_ contentManager: MPPlayableContentManager, initiatePlaybackOfContentItemAt indexPath: IndexPath, completionHandler: @escaping (Error?) -> Void) {
    var mutableIndexPath = indexPath
    let sourceIndex = mutableIndexPath.removeFirst()

    guard let items = self.getSourceItems(for: sourceIndex) else {
      completionHandler(BookPlayerError.UnableToLoadBooks("carplay_library_error".localized))
      return
    }

    let libraryItem = self.getItem(from: items, and: mutableIndexPath)

    guard let book = libraryItem.getBookToPlay() else {
      completionHandler(BookPlayerError.UnableToLoadBooks("carplay_library_error".localized))
      return
    }

    let message: [AnyHashable: Any] = ["command": "play",
                                       "identifier": book.relativePath!]

    NotificationCenter.default.post(name: .messageReceived, object: nil, userInfo: message)

    // Hack to show the now-playing-view on simulator
    // It has side effects on the initial state of the buttons of that view
    // But it's meant for development use only
    #if targetEnvironment(simulator)
    DispatchQueue.main.async {
      UIApplication.shared.endReceivingRemoteControlEvents()
      UIApplication.shared.beginReceivingRemoteControlEvents()
    }
    #endif

    completionHandler(nil)
  }

  func childItemsDisplayPlaybackProgress(at indexPath: IndexPath) -> Bool {
    return true
  }

  private func getItem(from items: [LibraryItem], and indexPath: IndexPath) -> LibraryItem {
    var mutableIndexPath = indexPath
    let index = mutableIndexPath.removeFirst()
    let item = items[index]

    if mutableIndexPath.isEmpty {
      return item
    }

    if let folder = item as? Folder,
       let folderItems = folder.items?.array as? [LibraryItem] {
      return getItem(from: folderItems, and: mutableIndexPath)
    } else {
      return item
    }
  }

  private func getSourceItems(for index: Int) -> [LibraryItem]? {
    // Recently played items
    if index == IndexGuide.tab.recentlyPlayed {
      return DataManager.getOrderedBooks()
    }

    // Library items
    return self.library?.items?.array as? [LibraryItem]
  }

  func setNowPlayingInfo(with book: Book) {
    var identifiers = [book.identifier!]

    if let folder = book.folder {
      identifiers.append(folder.identifier)
    }

    MPPlayableContentManager.shared().nowPlayingIdentifiers = identifiers
    MPPlayableContentManager.shared().reloadData()
  }
}
