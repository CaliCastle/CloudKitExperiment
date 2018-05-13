//
//  +Item.swift
//  CloudKitExperiment
//
//  Created by Cali Castle on 5/13/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import CoreData
import CloudKit
import Foundation

extension Item {
    
    convenience init(context: NSManagedObjectContext, record: CKRecord) {
        self.init(context: context)
        
        name = record["name"] as? String
        
        if let finished = record["finished"] as? Int {
            self.finished = finished == 1
        }
        
        recordName = record.recordID.recordName
    }
    
    public func updateFrom(record: CKRecord) {
        name = record["name"] as? String
        
        if let finished = record["finished"] as? Int {
            self.finished = finished == 1
        }
        
        if recordName != record.recordID.recordName {
            recordName = record.recordID.recordName
        }
    }
    
}
