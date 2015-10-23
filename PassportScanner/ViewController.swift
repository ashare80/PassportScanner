//
//  ViewController.swift
//  PassportScanner
//
//  Created by Edwin Vermeer on 9/8/15.
//  Copyright (c) 2015 Mirabeau. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.Portrait
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }

    @IBAction func startScan(sender: AnyObject) {
        let storyboard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let scanVC: MyScanViewController = storyboard.instantiateViewControllerWithIdentifier("PassportScanner") as! MyScanViewController
        let navigationController = UINavigationController(rootViewController: scanVC)
        self.presentViewController(navigationController, animated: true, completion: nil)
    }
}

