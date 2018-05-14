//
//  DetailViewController.swift
//  CloudKitExperiment
//
//  Created by Cali Castle on 5/12/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import UIKit
import CoreData
import CloudKit

class DetailViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    var managedObjectContext: NSManagedObjectContext? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let _ = list else { return }
        
        toolbarItems = [editButtonItem]
        
        navigationController?.setToolbarHidden(false, animated: false)
        
        tableView.allowsSelectionDuringEditing = true
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptForItem(_:)))
        navigationItem.rightBarButtonItem = addButton
        
        NotificationCenter.default.addObserver(forName: .init(rawValue: "ItemModify"), object: nil, queue: nil) { notification in
            if let recordID = notification.object as? CKRecordID {
                self.fetchQuery(recordID: recordID)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .init(rawValue: "ItemDelete"), object: nil, queue: nil) { notification in
            if let recordID = notification.object as? CKRecordID {
                self.deleteRecord(recordID: recordID)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .init(rawValue: "Foreground"), object: nil, queue: nil) { notification in
            self.fetchRecords()
        }
        
        subscribeForChanges()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        fetchRecords()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        guard let _ = list else { return }
        
        cloudDatabase.delete(withSubscriptionID: subscription.subscriptionID) { (id, error) in
            self.cloudDatabase.delete(withSubscriptionID: self.deleteSubscription.subscriptionID, completionHandler: { (_, _) in
                
            })
        }
    }

    var list: List? {
        didSet {
            title = "List [\(list?.title ?? "")]"
        }
    }
    
    fileprivate lazy var subscription: CKQuerySubscription = {
        let predicate = NSPredicate(format: "list = %@", CKRecordID(recordName: list!.recordName!))
        return CKQuerySubscription(recordType: String(describing: Item.self), predicate: predicate, options: [.firesOnRecordCreation, .firesOnRecordUpdate])
    }()
    
    fileprivate lazy var deleteSubscription: CKQuerySubscription = {
       let predicate = NSPredicate(format: "list = %@", CKRecordID(recordName: list!.recordName!))
        return CKQuerySubscription(recordType: String(describing: Item.self), predicate: predicate, options: .firesOnRecordDeletion)
    }()
    
    fileprivate func subscribeForChanges() {
        let notificationInfo = CKNotificationInfo()
        notificationInfo.alertActionLocalizationKey = "item.modify"
        notificationInfo.shouldBadge = true
        
        let deleteNotificationInfo = CKNotificationInfo()
        deleteNotificationInfo.alertActionLocalizationKey = "item.delete"
        deleteNotificationInfo.shouldBadge = true
        
        subscription.notificationInfo = notificationInfo
        deleteSubscription.notificationInfo = deleteNotificationInfo

        self.cloudDatabase.save(self.subscription) { (sub, error) in
            if error == nil {
                print("Subscription saved! \(sub?.notificationInfo?.alertActionLocalizationKey ?? "")")
            }
            
            self.cloudDatabase.save(self.deleteSubscription) { (sub, error) in
                if error == nil {
                    print("Subscription saved! \(sub?.notificationInfo?.alertActionLocalizationKey ?? "")")
                }
            }
        }
    }
    
    @objc
    private func promptForItem(_ sender: Any) {
        let actionController = UIAlertController(title: "Enter name of the item", message: nil, preferredStyle: .alert)
        actionController.addTextField {
            $0.placeholder = "Name"
            $0.returnKeyType = .done
            $0.autocapitalizationType = .sentences
        }
        actionController.addAction(UIAlertAction(title: "Add", style: .default, handler: { _ in
            self.insertNewItem(name: actionController.textFields!.first!.text!)
        }))
        actionController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(actionController, animated: true, completion: nil)
    }
    
    fileprivate func promptUpdateItem(at indexPath: IndexPath) {
        let item = fetchedResultsController.object(at: indexPath)
        let actionController = UIAlertController(title: "Change name of the item", message: nil, preferredStyle: .alert)
        actionController.addTextField {
            $0.text = item.name
            $0.placeholder = "Name"
            $0.returnKeyType = .done
            $0.autocapitalizationType = .sentences
        }
        
        actionController.addAction(UIAlertAction(title: "Update", style: .destructive, handler: { _ in
            self.updateItem(name: actionController.textFields!.first!.text!, for: item)
        }))
        actionController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(actionController, animated: true, completion: nil)
    }
    
    private func insertNewItem(name: String) {
        let context = self.fetchedResultsController.managedObjectContext
        let newItem = Item(context: context)
        
        // If appropriate, configure the new managed object.
        newItem.list = list
        newItem.name = name
        newItem.finished = false
        
        saveContext(context)
        
        syncToCloud(item: newItem, type: .insert)
    }
    
    private func updateItem(name: String, for item: Item) {
        let context = self.fetchedResultsController.managedObjectContext
        
        item.name = name
        
        saveContext(context)
        
        syncToCloud(item: item, type: .update)
    }
    
    fileprivate func fetchRecords() {
        guard let list = list else { return }
        let predicate = NSPredicate(format: "list = %@", CKRecordID(recordName: list.recordName!))

        cloudDatabase.perform(CKQuery(recordType: String(describing: Item.self), predicate: predicate), inZoneWith: nil) { (records, error) in
            if let error = error {
                print("Error when querying items: \(error.localizedDescription)")
            }
            
            if let records = records {
                self.syncRecords(records)
            }
        }
    }
    
    fileprivate func syncRecords(_ records: [CKRecord]) {
        let context = fetchedResultsController.managedObjectContext
        var allList = [Item]()

        records.forEach({
            allList.append(self.createOrUpdate($0))
            saveContext(context)
        })
        
        DispatchQueue.main.async {
            if let fetchedList = self.fetchedResultsController.fetchedObjects {
                Set(allList).symmetricDifference(Set(fetchedList)).forEach {
                    context.delete($0)
                }
            }
        }
    }
    
    fileprivate func fetchQuery(recordID: CKRecordID) {
        cloudDatabase.fetch(withRecordID: recordID) { (record, error) in
            guard error == nil else { print("Error when fetching query: \(error.debugDescription)"); return }
            
            if let record = record {
                let _ = self.createOrUpdate(record)
                self.saveContext(self.fetchedResultsController.managedObjectContext)
            }
        }
    }
    
    fileprivate func deleteRecord(recordID: CKRecordID) {
        guard let item = fetchedResultsController.fetchedObjects?.first(where: { $0.recordName == recordID.recordName }) else { return }
        
        let context = fetchedResultsController.managedObjectContext
        context.delete(item)
        
        saveContext(context)
        
        syncToCloud(item: item, type: .delete)
    }
    
    fileprivate func createOrUpdate(_ record: CKRecord) -> Item {
        let id = record.recordID.recordName
        let context = fetchedResultsController.managedObjectContext
        
        guard let item = fetchedResultsController.fetchedObjects?.first(where: { $0.recordName == id }) else {
            // Create
            let item = Item(context: context, record: record)
            item.list = self.list
            
            return item
        }
        
        // Update
        item.updateFrom(record: record)
        item.list = list
    
        return item
    }
    
    private func saveContext(_ context: NSManagedObjectContext? = nil) {
        // Save the context.
        do {
            if let context = context {
                try context.save()
            } else {
                try fetchedResultsController.managedObjectContext.save()
            }
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nserror = error as NSError
            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
        }
    }
    
    // MARK: - Table view
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 65
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
        let item = fetchedResultsController.object(at: indexPath)
        configureCell(cell, withItem: item)
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return fetchedResultsController.fetchedObjects?.count ?? 0
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            promptUpdateItem(at: indexPath)
        } else {
            let item = fetchedResultsController.object(at: indexPath)
            item.finished = !item.finished
            syncToCloud(item: item, type: .update)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let context = fetchedResultsController.managedObjectContext
            let item = fetchedResultsController.object(at: indexPath)
            
            syncToCloud(item: item, type: .delete)
            
            context.delete(item)
            saveContext(context)
        }
    }
    
    func configureCell(_ cell: UITableViewCell, withItem item: Item) {
        cell.textLabel!.text = item.name
        cell.accessoryType = item.finished ? .checkmark : .none
    }
    
    var fetchedResultsController: NSFetchedResultsController<Item> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<Item> = Item.fetchRequest()
        
        // Set the batch size to a suitable number.
        fetchRequest.fetchBatchSize = 20
        
        fetchRequest.predicate = NSPredicate(format: "list.title == %@", list?.title ?? "")
        
        fetchRequest.sortDescriptors = []
        
        let aFetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext! , sectionNameKeyPath: nil, cacheName: "\(list?.title ?? "")-Item")
        aFetchedResultsController.delegate = self
        _fetchedResultsController = aFetchedResultsController
        
        do {
            try _fetchedResultsController!.performFetch()
            
            fetchRecords()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nserror = error as NSError
            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
        }
        
        return _fetchedResultsController!
    }
    
    var _fetchedResultsController: NSFetchedResultsController<Item>? = nil

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
        case .delete:
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
        default:
            return
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath!], with: .fade)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .fade)
        case .update:
            configureCell(tableView.cellForRow(at: indexPath!)!, withItem: anObject as! Item)
        case .move:
            configureCell(tableView.cellForRow(at: indexPath!)!, withItem: anObject as! Item)
            tableView.moveRow(at: indexPath!, to: newIndexPath!)
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
    
    // MARK: - CloudKit
    
    let cloudDatabase = CKContainer.default().privateCloudDatabase
    
    fileprivate func syncToCloud(item: Item, type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            let record = CKRecord(recordType: "Item")
            record.setValue(item.name, forKeyPath: #keyPath(Item.name))
            record.setValue(item.finished, forKeyPath: #keyPath(Item.finished))
            
            // Add list 'belongs to' relationship
            let listID = CKRecordID(recordName: list!.recordName!)
            let reference = CKReference(recordID: listID, action: .deleteSelf)
            
            record.setValue(reference, forKeyPath: #keyPath(Item.list))
            
            cloudDatabase.save(record) { (record, error) in
                guard let record = record else { return }
                
                item.recordName = record.recordID.recordName
            }
        case .delete:
            if let recordName = item.recordName {
                cloudDatabase.delete(withRecordID: CKRecordID(recordName: recordName)) { (record, error) in
                    guard error == nil else { print("\(error.debugDescription)"); return }
                    
                    print("Record deleted")
                }
            }
        case .update:
            if let recordName = item.recordName {
                let newRecord = CKRecord(recordType: "Item", recordID: CKRecordID(recordName: recordName))
                newRecord.setValue(item.name, forKeyPath: #keyPath(Item.name))
                newRecord.setValue(item.finished, forKeyPath: #keyPath(Item.finished))
                
                // Add list relationship
                let listID = CKRecordID(recordName: list!.recordName!)
                let reference = CKReference(recordID: listID, action: .deleteSelf)
                
                newRecord.setValue(reference, forKeyPath: #keyPath(Item.list))
                
                let modifyOperation = CKModifyRecordsOperation(recordsToSave: [newRecord], recordIDsToDelete: nil)
                modifyOperation.savePolicy = .changedKeys
                modifyOperation.perRecordCompletionBlock = { (record, error) in
                    if let error = error {
                        print("Error when modifying record: \(error.localizedDescription)")
                    } else {
                        print("Record \(record.object(forKey: "name")!) modified")
                    }
                }
                
                cloudDatabase.add(modifyOperation)
            }
        default:
            return
        }
    }
    
}

