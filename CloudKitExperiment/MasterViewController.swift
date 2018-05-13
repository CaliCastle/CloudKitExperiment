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
    }

    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
        super.viewWillAppear(animated)
    }

    fileprivate func fetchRecords() {
        let query = CKQuery(recordType: "List", predicate: NSPredicate(value: true))
        cloudDatabase.perform(query, inZoneWith: nil) { (records, error) in
            if let error = error {
                print("Error when querying list: \(error.localizedDescription)")
            } else {
                if let records = records {
                    records.forEach({
                        let id = $0.recordID.recordName
                        
                        guard self.fetchedResultsController.fetchedObjects?.contains(where: { return $0.recordName == id }) == false else { return }
                        
                        let context = self.fetchedResultsController.managedObjectContext
                        let newList = List(context: context)
                        newList.title = $0.object(forKey: "title") as? String
                        newList.recordName = id
                        
                        // Save the context.
                        do {
                            try context.save()
                        } catch {
                            // Replace this implementation with code to handle the error appropriately.
                            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                            let nserror = error as NSError
                            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
                        }
                    })
                }
            }
        }
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
        let actionController = UIAlertController(title: "Change title of the list", message: nil, preferredStyle: .alert)
        actionController.addTextField {
            $0.placeholder = "Title"
            $0.returnKeyType = .done
            $0.autocapitalizationType = .words
        }
        actionController.addAction(UIAlertAction(title: "Add", style: .default, handler: { _ in
            let list = self.fetchedResultsController.object(at: indexPath)
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
    }
    
    func updateList(title: String, for list: List) {
        list.title = title
        
        saveContext(fetchedResultsController.managedObjectContext)
    }

    // MARK: - Segues

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            if let indexPath = tableView.indexPathForSelectedRow {
            let object = fetchedResultsController.object(at: indexPath)
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
                controller.list = object
                controller.managedObjectContext = managedObjectContext
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
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

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let context = fetchedResultsController.managedObjectContext
            context.delete(fetchedResultsController.object(at: indexPath))
                
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
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
        
        syncToCloud(list: anObject as! List, type: type)
        
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
            record.setValue(list.title!, forKey: "title")
            
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
                newRecord.setValue(list.title, forKey: "title")
                
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

