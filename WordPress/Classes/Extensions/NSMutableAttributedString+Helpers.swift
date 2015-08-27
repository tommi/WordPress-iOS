import Foundation


extension NSMutableAttributedString
{
    /**
    *  @details     Applies a collection of Styles to all of the substrings that match a given pattern
    *  @param       pattern     A Regex pattern that should be used to look up for matches
    *  @param       styles      Collection of styles to be applied on the matched strings
    */
    public func applyStylesToMatchesWithPattern(pattern: String, styles: [String: AnyObject]) {
        let regex = try! NSRegularExpression(pattern: pattern, options: NSRegularExpressionOptions.DotMatchesLineSeparators)
        let range = NSRange(location: 0, length: length)
        
        regex.enumerateMatchesInString(string, options: [], range: range) {
            (result: NSTextCheckingResult?, flags: NSMatchingFlags, stop: UnsafeMutablePointer<ObjCBool>) -> Void in
            
            if result != nil {
                self.addAttributes(styles, range: result!.range)
            }
        }
    }
}
