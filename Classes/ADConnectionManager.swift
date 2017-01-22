
// Handle WebServices Requests

import UIKit

import MBProgressHUD
import KSReachability

public enum HttpMethod: String {
    case GET = "GET"
    case POST = "POST"
}

public enum Response {
    case error(Error)
    case successWithData(Data)
    case successWithArray([AnyObject])
    case successWithDictionary([String: AnyObject])
}

open class ADConnectionManager: NSObject {

    static func generateString(_ dictionary: [String: String]) -> String {
        var str: String = ""
        for (key, value) in dictionary {
            str = str + "&" + key + "=" + value
        }
        return str.trimmingCharacters(in: CharacterSet(charactersIn: "&"))
    }

    // MARK:- Query String generator
    static func generateQueryString(_ dictionary: [String: String]) -> String {
        var str: String = ""
        for (key, value) in dictionary {
            str = str + "&" + key + "=" + value
        }
        return "?" + str.trimmingCharacters(in: CharacterSet(charactersIn: "&"))
    }

    static func addURLEncoding(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!
    }

    static func removeURLEncoding(_ string: String) -> String {
        return string.removingPercentEncoding!
    }

    // MARK:- URLRequest generator
    static func generateRequest(_ urlString: String,
                        dictionaryOfHeaders: [String: String]?,
                         postData: Data?,
                         requestType: HttpMethod) -> URLRequest {

        //Prepare url from url string
        let url = URL(string: urlString)
        //Prepare url request from url
        var request = URLRequest(url: url!)

        //Set http method type for request
        request.httpMethod = requestType.rawValue

        // set the request headers
        if let headers = dictionaryOfHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        //If body of request has some json data, set it's header fields and values, also add the post body in the request
        if let postBody = postData {
            request.setValue("\(postBody.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = postBody
        }

        // Set time interval of request
        request.timeoutInterval = 60

        return request
    }

    static func parseJSONData(_ data: Data?) -> Response {

        // Serialize the json format data into a swift object

        do {
            let obj = try JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions.allowFragments)
            print("Data:\(obj)")
            if let dictionary = obj as? [String: AnyObject] {
                return Response.successWithDictionary(dictionary)
            } else if let array = obj as? [AnyObject] {
                return Response.successWithArray(array)
            } else {
                let error = NSError(domain: "ADConnectionManager",
                 code: 501,
                 userInfo: ["Error occured in JSON Parsing": NSLocalizedDescriptionKey])
                return Response.error(error)
            }
        } catch {
            let error = NSError(domain: "ADConnectionManager",
                                code: 501,
                                userInfo: ["Error occured in JSON Parsing": NSLocalizedDescriptionKey])
            return Response.error(error)
        }
    }

    static func getDataFromServer(_ request: URLRequest, handler: @escaping (_ response: Response) -> Void) {

        //If internet is not available, print error message
        if !isInternetAvailable() {
            ADConnectionManager.showAlertMessage((UIApplication.shared.windows[0].rootViewController)!, title: "Internet Status", message: "Internet connection is not available", okButton: "Ok")
            ADConnectionManager.hideIndicator()
            return
        }

        // Configure a Session
        let session = URLSession.shared

        // Build a data task with the request and get data, response and error
        let task = session.dataTask(with: request) { (data: Data?, response: URLResponse?, error: Error?) in

                //If we get data properly and status code is 200
                if let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("Data is \(data)")
                    print("Response is \(httpResponse)")

                    return handler(Response.successWithData(data))

                } else if let error = error {
                    ADConnectionManager.hideIndicator()
                    return handler(Response.error(error))

                } else {
                    ADConnectionManager.hideIndicator()
                    print("Status code is not 200, invalid request/response")

                }
        }
        //Resume or start the task in background
        task.resume()
    }

    static func invokeRequestForJSON(_ request: URLRequest, handler: @escaping (_ response: Response) -> Void) {

        //Get data from server
        self.getDataFromServer(request) { (response: Response) in
            switch response {
            case let .successWithData(data):
                handler(self.parseJSONData(data))
            case let .error(error):
                handler(Response.error(error))

            default: break
            }
        }
    }

    static func isInternetAvailable() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)

        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }

        var flags = SCNetworkReachabilityFlags()
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) {
            return false
        }
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        return (isReachable && !needsConnection)
    }
}

extension ADConnectionManager {
    public class func showIndicator() {
        OperationQueue.main.addOperation {
            let spinnerActivity = MBProgressHUD.showAdded(to:(UIApplication.shared.keyWindow)!, animated: true)
            spinnerActivity.isUserInteractionEnabled = false
        }
    }

    public class func hideIndicator() {
        OperationQueue.main.addOperation {
            let _ = MBProgressHUD.hide(for: (UIApplication.shared.keyWindow)!, animated: true)
        }
    }
}

extension ADConnectionManager {
    public class func showAlertMessage(_ viewController: UIViewController, title: String, message: String, okButton: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let okButtonTitle = okButton {
            let okAction = UIAlertAction(title: okButtonTitle, style: .default, handler: { (action: UIAlertAction) in
                viewController.dismiss(animated: true, completion: nil)
            })
            alertController.addAction(okAction)
        }
        viewController.present(alertController, animated: true, completion: nil)
    }
}

extension ADConnectionManager {
    public class func uploadPhoto(_ request:URLRequest, image:UIImage, Handler:@escaping (Response) -> Void) -> URLSessionDataTask {
        var rqst = request
        let imageData = UIImagePNGRepresentation(image)
        rqst.httpMethod = "POST"
        let boundry = "---------------------------14737809831466499882746641449"
        let stringContentType = "multipart/form-data; boundary=\(boundry)"
        rqst.addValue(stringContentType, forHTTPHeaderField: "Content-Type")
        
        let dataToUpload = NSMutableData()
        
        // add boundry
        let boundryData = "\r\n--" + boundry + "\r\n"
        dataToUpload.append(boundryData.data(using: String.Encoding.utf8)!)
        
        // add file name
        let fileName = "Content-Disposition: form-data; name=\"uploadedfile\"; filename=\"abc.png\"\r\n"
        dataToUpload.append(fileName.data(using: String.Encoding.utf8)!)
        
        // add content type
        let contentType = "Content-Type: application/octet-stream\r\n\r\n"
        dataToUpload.append(contentType.data(using: String.Encoding.utf8)!)
        
        // add UIImage-Data
        dataToUpload.append(imageData!)
        
        // add end boundry
        let boundryEndData = "\r\n--" + boundry + "--\r\n"
        dataToUpload.append(boundryEndData.data(using: String.Encoding.utf8)!)
        
        // set HTTPBody to Request
        rqst.httpBody = dataToUpload as Data
        
        return self.invokeRequestForData(rqst, handler: Handler)
    }

}
