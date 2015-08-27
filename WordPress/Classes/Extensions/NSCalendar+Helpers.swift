import Foundation


extension NSCalendar
{
    public func daysElapsedSinceDate(date: NSDate) -> Int {
        let fromDate = date.normalizedDate()
        let toDate = NSDate().normalizedDate()
        
        let flags = NSCalendarUnit.Day
        let delta = components(flags, fromDate: fromDate, toDate: toDate, options: NSCalendarOptions())
        
        return delta.day
    }
}
