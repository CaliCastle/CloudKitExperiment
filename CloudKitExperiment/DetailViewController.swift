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
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptForItem(_:)))
        navigationItem.rightBarButtonItem = addButton
    }

    var list: List? {
        didSet {
            title = "List [\(list?.title ?? "")]"
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
    
    private func insertNewItem(name: String) {
        let context = self.fetchedResultsController.managedObjectContext
        let newItem = Item(context: context)
        
        // If appropriate, configure the new managed object.
        newItem.list = list
        newItem.name = name
        newItem.finished = false
        
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
        tableView.deselectRow(at: indexPath, animated: true)
        
        let item = fetchedResultsController.object(at: indexPath)
        item.finished = !item.finished
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
        
        syncToCloud(item: anObject as! Item, type: type)
        
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
            record.setValue(item.name, forKey: "name")
            record.setValue(item.finished, forKey: "finished")
            record.setValue(list!.recordName, forKeyPath: "listID")
            
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
                newRecord.setValue(item.name, forKey: "name")
                newRecord.setValue(item.finished, forKey: "finished")
                newRecord.setValue(list!.recordName, forKeyPath: "listID")
                
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

