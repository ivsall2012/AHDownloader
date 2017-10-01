//
//  AHDataTaskManager.swift
//  AHDownloadTool
//
//  Created by Andy Tong on 6/22/17.
//  Copyright © 2017 Andy Tong. All rights reserved.
//

import UIKit

private let AHDataTaskManagerDispatchQueueName = "AHDataTaskManagerDispatchQueueName"

public class AHDataTaskManager: NSObject {
    public static var timeout: TimeInterval = 0
    public static var maxConcurrentTasks: Int = 1 {
        didSet {
            guard maxConcurrentTasks > 0 else {return}
            AHDataTask.maxConcurrentTasks = maxConcurrentTasks
        }
    }
    
    /// The total tasks currently in the stack, including ones downloading and pending.
    public static var numberOfTasks: Int {
        return dataTaskDict.keys.count
    }
    
    // The serial queue use to add download tasks to ensure thread safety.
    fileprivate static var dispatchQueue: DispatchQueue = {
        return DispatchQueue(label: AHDataTaskManagerDispatchQueueName)
    }()
    fileprivate static var dataTaskDict = [String: AHDataTask]()
}

public extension AHDataTaskManager {
    /// If it has the task, but not downloading, thhis means the task is pending.
    public static func hasTask(_ urlStr: String) -> Bool{
        if let _ = dataTaskDict[urlStr] {
            return true
        }else{
            return false
        }
        
    }
    
    /// Is this task acutally paused but still in the download stack?
    /// Will return false when there's no such task.
    public static func isTaskPaused(_ urlStr: String) -> Bool{
        if let task = dataTaskDict[urlStr] {
            return task.state == .pausing
        }else{
            return false
        }
    }
    
    public static func getTaskTempFilePath(_ urlStr: String) -> String? {
        if let task = dataTaskDict[urlStr] {
            return task.fileTempPath
        }else{
            return nil
        }
    }
    
    public static func donwload(fileName: String?=nil, url: String, fileSizeCallback: ((_ fileSize: UInt64) -> Void)?, progressCallback: ((_ progress: Double) -> Void)?, successCallback: ((_ filePath: String) -> Void)?, failureCallback: ((_ error: Error?) -> Void)?) {
        
        self.donwload(fileName: fileName, tempDir: nil, cachePath: nil, url: url, fileSizeCallback: fileSizeCallback, progressCallback: progressCallback, successCallback: successCallback, failureCallback: failureCallback)
        
    }
    /// This method is thread safe.
    public static func donwload(fileName: String?, tempDir: String?, cachePath: String?,url: String, fileSizeCallback: ((_ fileSize: UInt64) -> Void)?, progressCallback: ((_ progress: Double) -> Void)?, successCallback: ((_ filePath: String) -> Void)?, failureCallback: ((_ error: Error?) -> Void)?) {
        
        dispatchQueue.async {
            var dataTask = dataTaskDict[url]
            if dataTask == nil {
                dataTask = AHDataTask()
                dataTask?.timeout = timeout
                dataTask?.fileName = fileName
                dataTask?.tempDir = tempDir
                dataTask?.cacheDir = cachePath
                dataTaskDict[url] = dataTask
                
                // Default AHDataTask's callback queue is main
                dataTask?.donwload(url: url, fileSizeCallback: fileSizeCallback, progressCallback: progressCallback, successCallback: { (path) in
                    
                    DispatchQueue.main.async {
                        self.dataTaskDict.removeValue(forKey: url)
                        successCallback?(path)
                    }
                
                }, failureCallback: { (error) in
                    DispatchQueue.main.async {
                        self.dataTaskDict.removeValue(forKey: url)
                        failureCallback?(error)
                    }
                })
                
            }else{
                print("download task repeated!")
            }
        }
        
    }
    
    public static func resume(url: String) {
        if let dataTask = dataTaskDict[url] {
            dataTask.resume()
        }
    }
    
    public static func resumeAll() {
        for url in dataTaskDict.keys {
            resume(url: url)
        }
    }
    
    public static func pause(url: String) {
        if let dataTask = dataTaskDict[url] {
            dataTask.pause()
        }
    }
    
    public static func pauseAll() {
        for url in dataTaskDict.keys {
            pause(url: url)
        }
    }
    
    /// When cancel, the temporary file will be deleted as well.
    public static func cancel(url: String) {
        if let dataTask = dataTaskDict[url] {
            dataTask.cancel()
            dataTaskDict.removeValue(forKey: url)
        }
    }
    
    /// When cancel, the temporary file will be deleted as well.
    public static func cancelAll() {
        for url in dataTaskDict.keys {
            cancel(url: url)
        }
    }
    
}







