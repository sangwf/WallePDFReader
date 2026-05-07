import CoreServices
import Foundation

let bundleID = "local.wallepdfreader" as CFString
let pdfUTI   = "com.adobe.pdf"        as CFString

let status = LSSetDefaultRoleHandlerForContentType(pdfUTI, .all, bundleID)

if status == 0 {
    print("✓ WallePDFReader is now the default for PDFs")
} else {
    print("✗ Failed (OSStatus \(status))")
    exit(1)
}
