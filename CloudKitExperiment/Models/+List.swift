//
//  +List.swift
//  CloudKitExperiment
//
//  Created by Cali Castle on 5/13/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import Foundation
import CoreData
import CloudKit

extension List {
    
    convenience init(context: NSManagedObjectContext, record: CKRecord) {
        self.init(context: context)
        
        title = record["title"] as? String
        recordName = record.recordID.recordName
    }
    
    public func updateFrom(record: CKRecord) {
        title = record["title"] as? String
        
        if recordName != record.recordID.recordName {
            recordName = record.recordID.recordName
        }
    }
    
}
