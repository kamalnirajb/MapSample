//
//  ViewController.swift
//  MapSample
//
//  Created by Niraj Kumar on 3/9/17.
//  Copyright © 2017 Niraj. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import CoreMotion

class HomeVC: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    
    // UI variables
    @IBOutlet weak var mapview: MKMapView!
    @IBOutlet weak var btnBeginWalk: UIButton!
    @IBOutlet weak var lblDistanceTravelled: UILabel!
    
    // Data variables
    // Start time to validate to fetch the update in regular time interval
    var startTime:Date?
    
    // Array of locations
    var myLocations:[CLLocation] = []
    
    // Number of locations to maintain the history for calculating the accurate distance
    let numberOfLocations:Int = 5
    
    // Location manager
    let locationManager:CLLocationManager = CLLocationManager()
    
    // Distance Filter for minimum distance to fetch the location update
    let distanceFilter = 5
    //// niraj
    // Time interval to fetch a new location(seconds)
    let timeFilter = 10.0
    
    // maintain the timing
    var timer = Timer()
    
    // Maximum waiting time to move from one location
    let maximumWaitingTimeToMove = 60
    
    // Horizontal accuracy in meters that is minimum required
    let requiredHorizontalAccuracy = 20.0
    
    // Last recorded location
    var lastRecordedLocation:CLLocation?
    
    // Total distance covered
    var totalDistance:CLLocationDistance = 0.0
    
    // NIraj
    // Time in seconds to decide if the distance to be calculated
    let validTimeInterval = 3.0
    
    // Valid distance to stop
    let validDistance = 3.0
    
    // Source location to show on the map
    var sourceLocation:CLLocation?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initLocationManager()
        timer = Timer.scheduledTimer(withTimeInterval: timeFilter, repeats: true, block: { (t) in
            if self.isLocationEnabled() {
                self.locationManager.requestLocation()
            }
        })
        setAccelerometer()
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setAccelerometer() {
        let cmmanager:CMMotionManager = CMMotionManager()
        if cmmanager.isGyroAvailable, cmmanager.isGyroActive {
            print(cmmanager.gyroData)
        }else {
            print("Gyro not available")
        }
        
    }
    
    func getInterval() -> Int {
        if let st:Date = startTime {
            return Int(Date().timeIntervalSince(st))
        }
        return 0
    }
    
    
    /// Called on click of begin walk button
    ///
    /// - Parameter sender: UIButton
    @IBAction func btnBeginWalkClicked(_ sender: Any) {
        if isLocationEnabled() {
            self.btnBeginWalk.tag = 1 - self.btnBeginWalk.tag
            if self.btnBeginWalk.tag == 0 {
                startTime = nil
                self.btnBeginWalk.setTitle("Begin Walk", for: .normal)
                locationManager.stopUpdatingLocation()
            }else {
                sourceLocation = nil
                self.lblDistanceTravelled.text = "0.0 KM"
                startTime = Date()
                self.mapview.removeAnnotations(self.mapview.annotations)
                self.btnBeginWalk.setTitle("Stop Walk", for: .normal)
                locationManager.startUpdatingLocation()
            }
        }
    }
    
    
    /// Check if location service is enabled and authroized permission is provided
    ///
    /// - Returns: true if both conditions are true, else false
    func isLocationEnabled() -> Bool {
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .denied, .notDetermined, .restricted:
                print("Please enable location services")
                locationManager.requestAlwaysAuthorization()
                return false
            default:
                return true
            }
        }else{
            print("Please enable location services")
            return false
        }
    }
    
    /// Location manager initializer
    func initLocationManager() {
        if isLocationEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestLocation()
            locationManager.delegate = self
        }else{
            locationManager.requestAlwaysAuthorization()
            print("Please enable location services")
        }
    }
    
    
    /// Called on getting a new location
    ///
    /// - Parameters:
    ///   - manager: locationManager
    ///   - locations: list of locations
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if myLocations.count == 0 {
            myLocations.append(locations[0])
        }else if let st:Date = startTime, locations.last?.timestamp.compare(st) == .orderedDescending, locations[0].horizontalAccuracy <= requiredHorizontalAccuracy {
            myLocations.append(locations[0])
            if myLocations.count > 5 {
                myLocations = Array(myLocations.suffix(5))
            }
            let directionRequest:MKDirectionsRequest = MKDirectionsRequest()
            if sourceLocation == nil {
                sourceLocation = locations.first
                let sourcePlacemark:MKPlacemark = MKPlacemark(coordinate: sourceLocation!.coordinate, addressDictionary: nil)
                let sourceMapItem:MKMapItem = MKMapItem(placemark:sourcePlacemark)
                let sourceAnnotation:MKPointAnnotation = MKPointAnnotation()
                sourceAnnotation.title = "Begining location for walk"
                sourceAnnotation.coordinate = (sourceLocation?.coordinate)!
                self.mapview.showAnnotations([sourceAnnotation], animated: true)
                directionRequest.source = sourceMapItem
            }
            
            
            // if the user is at the same place for a minute, stop updating the location and ping every 10 seconds to fetch the new location of the user to check if needs to begin the location update
            if let lrl:CLLocation = lastRecordedLocation, lrl.distance(from: locations[0]) <= validDistance, getInterval() > maximumWaitingTimeToMove{
                var isToStopUpdating = false
                for recLocation in myLocations {
                    isToStopUpdating = recLocation.speed < 1
                }
                manager.stopUpdatingLocation()
                if isToStopUpdating {
                    startTime = Date()
                    timer.invalidate()
                    timer.fire()
                }
            }else {
                // Get the last location to calculate the distance
                if lastRecordedLocation == nil {
                    lastRecordedLocation = (myLocations.count > 0) ? myLocations[0] : locations[0]
                }
                
                var newLocation:CLLocation? = nil
                var newLocationAccuracy = requiredHorizontalAccuracy
                
                // Check which location among recorded locations has the required horizontal accuracy and consider that as the new location
                for location in myLocations {
                    if Date().timeIntervalSinceReferenceDate - location.timestamp.timeIntervalSinceReferenceDate <= validTimeInterval {
                        if location.horizontalAccuracy <= newLocationAccuracy, location != lastRecordedLocation {
                            newLocationAccuracy = location.horizontalAccuracy
                            newLocation = location
                        }
                    }
                }
                // In case none of the locations are in the required location because of weak GPS signals, we can consider the last location as the new location
                if newLocation == nil {
                    newLocation = locations.last
                }
                
                // Find the distance and set it to the label to show the user the distance he travelled
                if let distance:CLLocationDistance = newLocation?.distance(from: lastRecordedLocation!) {
                    totalDistance = totalDistance + distance
                    DispatchQueue.main.async {
                        self.lblDistanceTravelled.text = "\((self.totalDistance.rounded()) / 1000) KM"
                        let region = MKCoordinateRegionMakeWithDistance((self.lastRecordedLocation?.coordinate)!, 1.0, 1.0)
                        self.mapview.setRegion(region, animated: true)
                    }
                    
                    // Set annotations
                    let destinationPlacemark:MKPlacemark = MKPlacemark(coordinate: (newLocation?.coordinate)!, addressDictionary: nil)
                    let destinationMapItem:MKMapItem = MKMapItem(placemark: destinationPlacemark)
                    
                    let destinationAnnotation:MKPointAnnotation = MKPointAnnotation()
                    destinationAnnotation.title = "Current location while walk"
                    destinationAnnotation.coordinate = (newLocation?.coordinate)!
                 
                    self.mapview.showAnnotations([self.mapview.annotations.first!, destinationAnnotation], animated: true)
                    directionRequest.destination = destinationMapItem
                    directionRequest.transportType = .walking
                    
                    // Calculate the direction
                    let directions = MKDirections(request: directionRequest)
                    
                    directions.calculate(completionHandler: { (response, error) in
                        guard let response = response else {
                            if let error = error {
                                print("Error: \(error)")
                            }
                            
                            return
                        }
                        
                        let route = response.routes[0]
                        
                        self.mapview.add((route.polyline), level: MKOverlayLevel.aboveLabels)
                        let rect = route.polyline.boundingMapRect
                        self.mapview.setRegion(MKCoordinateRegionForMapRect(rect), animated: true)
                    })
                    
                }
                // Update the last recorded location
                lastRecordedLocation = newLocation
            }
        }
    }
    
    
    /// Called on error of location update or unauthorized access
    ///
    /// - Parameters:
    ///   - manager: locationManager
    ///   - error: error
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error.localizedDescription)
    }
    
    
    /// Called on update the location permission or locatin access
    ///
    /// - Parameters:
    ///   - manager: locationManager
    ///   - status: status of the location service
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if isLocationEnabled() {
            manager.requestLocation()
        }
    }
    
    /// Mark MKMapViewDelegate methods
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        var annotationView = self.mapview.dequeueReusableAnnotationView(withIdentifier: "walkpin")
        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: "walkpin")
            annotationView?.canShowCallout = true
        }else {
            annotationView?.annotation = annotation
        }
        annotationView?.image = UIImage(named: "pin")
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let routeRenderer = MKPolylineRenderer(overlay: overlay)
        routeRenderer.strokeColor = UIColor.blue
        routeRenderer.lineWidth = 2.0
        routeRenderer.lineCap = .butt
        
        return routeRenderer
    }
    
}

