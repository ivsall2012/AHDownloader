//
//  AHDownloader.swift
//  Pods
//
//  Created by Andy Tong on 8/4/17.
//
//

import Foundation
import AHDownloadTool

struct DelegateContainer: Equatable {
    weak var delegate: AHDownloaderDelegate?
    
    public static func ==(lhs: DelegateContainer, rhs: DelegateContainer) -> Bool {
        return lhs.delegate === rhs.delegate
    }
}

struct DownloadTask {
    var urlStr: String
    
    var localFilePath: String?
    var unfinishLocalFilePath: String?
    var progress: Double?
}

/// The delegate of this protocol should NOT be doing anything related to saving info into the DB!! If you need downloaded file path, query the DB.
public protocol AHDownloaderDelegate: class {
    func downloaderWillStartDownload(url:String)
    func downloaderDidStartDownload(url:String)
    func downloaderDidUpdate(url:String, progress:Double)
    func downloaderDidUpdate(url:String, fileSize:Int)
    /// The path is used to storing downloading data
    func downloaderDidUpdate(url: String, unfinishedLocalPath: String)
    func downloaderDidFinishDownload(url:String, localFilePath: String)
    func downloaderDidPaused(url: String)
    func downloaderDidPausedAll()
    func downloaderDidResumedAll()
    func downloaderDidResume(url:String)
    func downloaderCancelAll()
    func downloaderDidCancel(url:String)
    /// The downloader already handled removing unfinished files for you.
    /// This is just a notification. You should delete unfinishedFilePath for your data models.
    func downloaderDeletedUnfinishedTaskFiles(urls: [String])
    
    /// Will use first delegate that returns a non-nil string
    func downloaderForFileName(url: String) -> String?
    
}

extension AHDownloaderDelegate {
    public func downloaderWillStartDownload(url:String){}
    public func downloaderDidStartDownload(url:String){}
    public func downloaderDidUpdate(url:String, progress:Double){}
    public func downloaderDidUpdate(url:String, fileSize:UInt64){}
    public func downloaderDidUpdate(url: String, unfinishedLocalPath: String){}
    public func downloaderDidFinishDownload(url:String, localFilePath: String){}
    public func downloaderDidPaused(url: String){}
    public func downloaderDidPausedAll(){}
    public func downloaderDidResumedAll(){}
    public func downloaderDidResume(url:String){}
    public func downloaderCancelAll(){}
    public func downloaderDidCancel(url:String){}
    public func downloaderDeletedUnfinishedTaskFiles(urls: [String]){}
    /// Includeing file extension
    public func downloaderForFileName(url: String) -> String?{return nil}
}

public class AHDownloader {
    public static var timeout: TimeInterval = 8.0 {
        didSet {
            let timeout = AHDownloader.timeout
            AHDataTaskManager.timeout = timeout
        }
    }
    
    fileprivate static var delegateContainers = [DelegateContainer]()
    
    /// [url: DownloadTask]
    fileprivate static var taskDict = [String: DownloadTask]()

    
    /// Downloader keeps delegate object weakly,so don't need to remove delegate manually.
    /// The same delegate might be added mutiple times without any duplication.
    public static func addDelegate(_ delegate: AHDownloaderDelegate) {
        self.checkDelegateContainers()
        for i in 0..<self.delegateContainers.count {
            let delegateContainer = self.delegateContainers[i]
            if delegateContainer.delegate === delegate {
                // duplicate
                return
            }
        }
        
        let container = DelegateContainer(delegate: delegate)
        self.delegateContainers.append(container)
    }
    
    public static func removeDelegate(_ delegate: AHDownloaderDelegate) {
        var index: Int?
        for i in 0..<self.delegateContainers.count {
            let delegateContainer = self.delegateContainers[i]
            if delegateContainer.delegate === delegate {
                index = i
                break
            }
        }
        if index != nil {
            self.delegateContainers.remove(at: index!)
        }
    }
    
    /// Delete unfinishFiles for currently downloading yet unfinished tasks.
    /// Will cancel tasks first.
    public static func deleteUnfinishedTasks(_ urls: [String], _ completion:(()->Void)? ) {
        for url in urls {
            self.cancel(url: url)
        }
        DispatchQueue.global().async {
            
            for url in urls {
                if let task = self.taskDict[url]{
                    if let unfinished = task.unfinishLocalFilePath {
                        AHFileTool.remove(filePath: unfinished)
                    }
                }
            }
            
            // Main thread to send notifications, the receiver will be at main too.
            DispatchQueue.main.async {
                self.checkDelegateContainers()
                for container in self.delegateContainers {
                    container.delegate?.downloaderDeletedUnfinishedTaskFiles(urls: urls)
                }
                
                completion?()
            }
            
        }
    }
    
    public static func hasTask(_ url: String) -> Bool {
        return AHDataTaskManager.hasTask(url)
    }
    
    // Is this task acutally paused but still in the download stack?
    public static func isTaskPaused(_ url: String) -> Bool {
        return AHDataTaskManager.isTaskPaused(url)
    }
    
    
    /// Return the task's unfinishedFilePath
    public static func download(_ url: String){
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderWillStartDownload(url: url)
        }
        
        let fileName = getFileName(url)
        
        AHDataTaskManager.donwload(fileName: fileName, url: url, fileSizeCallback: { (fileSize) in
            self.checkDelegateContainers()
            let tempPath = AHDataTaskManager.getTaskTempFilePath(url)
            for container in self.delegateContainers {
                container.delegate?.downloaderDidUpdate(url: url, FileSize: fileSize)
                
                if tempPath != nil {
                    container.delegate?.downloaderDidUpdate(url: url, unfinishedLocalPath: tempPath!)
                }
                
            }
        }, progressCallback: { (progress) in
            // not gonna check, since the updating progress will be too frequent.
            // only checkDelegateContainers() when actions required.
            for container in self.delegateContainers {
                container.delegate?.downloaderDidUpdate(url: url, progress: progress)
            }
            
        }, successCallback: { (filePath) in
            self.checkDelegateContainers()
            for container in self.delegateContainers {
                container.delegate?.downloaderDidFinishDownload(url: url, localFilePath: filePath)
            }
            
        }) { (error) in
            print("downloadError:\(error!)")
            self.checkDelegateContainers()
            for container in self.delegateContainers {
                container.delegate?.downloaderDidCancel(url: url)
            }
        }
        
        for container in self.delegateContainers {
            container.delegate?.downloaderDidStartDownload(url: url)
        }
    }
    
    public static func pause(url: String) {
        AHDataTaskManager.pause(url: url)
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderDidPaused(url: url)
        }
        
    }
    public static func pauseAll() {
        AHDataTaskManager.pauseAll() 
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderDidPausedAll()
        }
    }
    
    
    public static func resume(url: String) {
        AHDataTaskManager.resume(url: url)
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderDidResume(url: url)
        }
    }
    public static func resumeAll() {
        AHDataTaskManager.resumeAll()
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderDidResumedAll()
        }
    }
    
    
    
    public static func cancel(url: String) {
        AHDataTaskManager.cancel(url: url)
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderDidCancel(url: url)
        }
    }
    
    public static func cancelAll() {
        AHDataTaskManager.cancelAll()
        self.checkDelegateContainers()
        for container in self.delegateContainers {
            container.delegate?.downloaderCancelAll()
        }
    }
    

}


//MARK:- Helpers
extension AHDownloader {
    fileprivate static func getFileName(_ url: String) -> String {
        self.checkDelegateContainers()
        var name: String?
        for container in self.delegateContainers {
            if let theName = container.delegate?.downloaderForFileName(url: url){
                name = theName
                break
            }
        }
        
        if name == nil {
            let uuid = UUID.init().uuidString
            name = "\(uuid)_unnamed_file"
        }
        return name!
    }
    
    /// This method will remove nil delegates.
    fileprivate static func checkDelegateContainers() {
        var neededToRemove = [Int]()
        for i in 0..<self.delegateContainers.count {
            let delegateContainer = self.delegateContainers[i]
            if delegateContainer.delegate == nil {
                neededToRemove.append(i)
            }
        }
        for i in neededToRemove {
            self.delegateContainers.remove(at: i)
        }
    }
}







