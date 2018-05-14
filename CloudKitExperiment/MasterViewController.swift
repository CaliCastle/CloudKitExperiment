//
//  MasterViewController.swift
//  CloudKitExperiment
//
//  Created by Cali Castle on 5/12/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import UIKit
import CoreData
import CloudKit

class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    var detailViewController: DetailViewController? = nil
    var managedObjectContext: NSManagedObjectContext? = nil

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "All Lists"
        
        navigationItem.leftBarButtonItem = editButtonItem

        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptForItem(_:)))
        navigationItem.rightBarButtonItem = addButton
        
        tableView.allowsSelectionDuringEditing = true
        
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
            detailViewController?.managedObjectContext = managedObjectContext
        }
        
        NotificationCenter.default.addObserver(forName: .init(rawValue: "ListModify"), object: nil, queue: nil) { notification in
            if let recordID = notification.object as? CKRecordID {
                self.fetchQuery(recordID: recordID)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .init(rawValue: "ListDelete"), object: nil, queue: nil) { notification in
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
        super.viewWillAppear(animated)
    }

    fileprivate func subscribeForChanges() {
        // Subscribe for changes
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(recordType: String(describing: List.self), predicate: predicate, options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        let deleteSubscription = CKQuerySubscription(recordType: String(describing: List.self), predicate: predicate, options: .firesOnRecordDeletion)
        
        let notificationInfo = CKNotificationInfo()
        notificationInfo.alertActionLocalizationKey = "list.modify"
        notificationInfo.shouldSendContentAvailable = true
        
        let deleteNotificationInfo = CKNotificationInfo()
        deleteNotificationInfo.alertActionLocalizationKey = "list.delete"
        deleteNotificationInfo.shouldSendContentAvailable = true
        
        subscription.notificationInfo = notificationInfo
        deleteSubscription.notificationInfo = deleteNotificationInfo
        
        DispatchQueue.main.async {
            self.cloudDatabase.save(subscription) { (sub, error) in
                if error == nil {
                    print("Subscription saved! \(sub?.notificationInfo?.alertActionLocalizationKey ?? "")")
                }
                
                self.cloudDatabase.save(deleteSubscription) { (sub, error) in
                    if error == nil {
                        print("Subscription saved! \(sub?.notificationInfo?.alertActionLocalizationKey ?? "")")
                    }
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
    
    fileprivate func fetchRecords() {
        let query = CKQuery(recordType: String(describing: List.self), predicate: NSPredicate(value: true))
        cloudDatabase.perform(query, inZoneWith: nil) { (records, error) in
            if let error = error {
                print("Error when querying list: \(error.localizedDescription)")
            } else {
                if let records = records {
                    self.syncRecords(records)
                }
            }
        }
    }
    
    fileprivate func syncRecords(_ records: [CKRecord]) {
        let context = fetchedResultsController.managedObjectContext
        var allList = [List]()
        
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
    
    fileprivate func createOrUpdate(_ record: CKRecord) -> List {
        let id = record.recordID.recordName
        let context = self.fetchedResultsController.managedObjectContext
        
        guard let list = fetchedResultsController.fetchedObjects?.first(where: { $0.recordName == id }) else {
            // Create
            return List(context: context, record: record)
        }
        
        // Update
        list.updateFrom(record: record)
        
        return list
    }
    
    fileprivate func deleteRecord(recordID: CKRecordID) {
        guard let list = fetchedResultsController.fetchedObjects?.first(where: { $0.recordName == recordID.recordName }) else { return }
        
        let context = fetchedResultsController.managedObjectContext
        context.delete(list)
        
        saveContext(context)
        
        syncToCloud(list: list, type: .delete)
    }
    
    fileprivate func saveContext(_ context: NSManagedObjectContext) {
        // Save the context.
        do {
            try context.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nserror = error as NSError
            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
        }
    }

    @objc
    fileprivate func promptForItem(_ sender: Any) {
        let actionController = UIAlertController(title: "Enter title of the list", message: nil, preferredStyle: .alert)
        actionController.addTextField {
            $0.placeholder = "Title"
            $0.returnKeyType = .done
            $0.autocapitalizationType = .words
        }
        actionController.addAction(UIAlertAction(title: "Add", style: .default, handler: { _ in
            self.insertNewList(title: actionController.textFields!.first!.text!)
        }))
        actionController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(actionController, animated: true, completion: nil)
    }
    
    fileprivate func promptForUpdate(at indexPath: IndexPath) {
        let list = fetchedResultsController.object(at: indexPath)
        let actionController = UIAlertController(title: "Change title of the list", message: nil, preferredStyle: .alert)
        actionController.addTextField {
            $0.text = list.title
            $0.placeholder = "Title"
            $0.returnKeyType = .done
            $0.autocapitalizationType = .words
        }
        actionController.addAction(UIAlertAction(title: "Update", style: .default, handler: { _ in
            self.updateList(title: actionController.textFields!.first!.text!, for: list)
        }))
        actionController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        present(actionController, animated: true, completion: nil)
    }
    
    func insertNewList(title: String) {
        let context = self.fetchedResultsController.managedObjectContext
        let newList = List(context: context)

        let uuid = UUID().uuidString
        newList.recordName = uuid
        
        // If appropriate, configure the new managed object.
        newList.title = title

        saveContext(context)
        
        syncToCloud(list: newList, type: .insert)
    }
    
    func updateList(title: String, for list: List) {
        list.title = title
        
        saveContext(fetchedResultsController.managedObjectContext)
        
        syncToCloud(list: list, type: .update)
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            if let indexPath = tableView.indexPathForSelectedRow {
                let object = fetchedResultsController.object(at: indexPath)
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
                controller.managedObjectContext = managedObjectContext
                controller.list = object
            }
        }
    }

    // MARK: - Table View

    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultsController.sections![section]
        return sectionInfo.numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let list = fetchedResultsController.object(at: indexPath)
        configureCell(cell, withList: list)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            promptForUpdate(at: indexPath)
        } else {
            performSegue(withIdentifier: "showDetail", sender: nil)
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 56
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let context = fetchedResultsController.managedObjectContext
            let list = fetchedResultsController.object(at: indexPath)
            
            syncToCloud(list: list, type: .delete)
            
            context.delete(list)

            saveContext(context)
        }
    }

    func configureCell(_ cell: UITableViewCell, withList list: List) {
        cell.textLabel!.text = list.title
    }

    // MARK: - Fetched results controller

    var fetchedResultsController: NSFetchedResultsController<List> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<List> = List.fetchRequest()
        
        // Set the batch size to a suitable number.
        fetchRequest.fetchBatchSize = 20
        
        // Edit the sort key as appropriate.
        let sortDescriptor = NSSortDescriptor(key: #keyPath(List.title), ascending: true)
        
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        // Edit the section name key path and cache name if appropriate.
        // nil for section name key path means "no sections".
        let aFetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.managedObjectContext!, sectionNameKeyPath: nil, cacheName: "Lists")
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
    
    var _fetchedResultsController: NSFetchedResultsController<List>? = nil

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
                configureCell(tableView.cellForRow(at: indexPath!)!, withList: anObject as! List)
            case .move:
                configureCell(tableView.cellForRow(at: indexPath!)!, withList: anObject as! List)
                tableView.moveRow(at: indexPath!, to: newIndexPath!)
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
    
    // MARK: - CloudKit
    
    let cloudDatabase = CKContainer.default().privateCloudDatabase
    
    fileprivate func syncToCloud(list: List, type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            let record = CKRecord(recordType: "List", recordID: CKRecordID(recordName: list.recordName ?? ""))
            record.setValue(list.title!, forKeyPath: #keyPath(List.title))
            
            cloudDatabase.save(record) { (record, error) in
                guard let record = record else { return }
                
                print("Record created: \(record.recordID.recordName)")
            }
        case .delete:
            if let recordName = list.recordName {
                cloudDatabase.delete(withRecordID: CKRecordID(recordName: recordName)) { (record, error) in
                    guard error == nil else { print("\(error.debugDescription)"); return }
                    
                    print("Record deleted")
                }
            }
        case .update:
            if let recordName = list.recordName {
                let newRecord = CKRecord(recordType: "List", recordID: CKRecordID(recordName: recordName))
                newRecord.setValue(list.title, forKeyPath: #keyPath(List.title))
                
                let modifyOperation = CKModifyRecordsOperation(recordsToSave: [newRecord], recordIDsToDelete: nil)
                modifyOperation.savePolicy = .changedKeys
                modifyOperation.perRecordCompletionBlock = { (record, error) in
                    if let error = error {
                        print("Error when modifying record: \(error.localizedDescription)")
                    } else {
                        print("Record \(record.object(forKey: "title")!) modified")
                    }
                }
                
                cloudDatabase.add(modifyOperation)
            }
        default:
            return
        }
    }

}

// MARK: - Keyboard Shortcuts

extension MasterViewController {
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "N", modifierFlags: .command, action: #selector(commandPressed(_:)), discoverabilityTitle: "Create a new list"),
            UIKeyCommand(input: "E", modifierFlags: .command, action: #selector(commandPressed(_:)), discoverabilityTitle: "Edit a list")
        ]
        
        return commands
    }
    
    @objc
    fileprivate func commandPressed(_ command: UIKeyCommand) {
        if let input = command.input {
            switch input {
            case "E":
                if let indexPath = tableView.indexPathForSelectedRow {
                    promptForUpdate(at: indexPath)
                }
                
                return
            case "N":
                promptForItem(input)
            default:
                return
            }
        }
    }
    
}
