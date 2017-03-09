import android.content {
    Context
}
import android.content.pm {
    PackageManager
}
import android.content.res {
    XmlResourceParser
}
import android.os {
    Process
}
import android.util {
    Base64
}

import com.example.android.uamp.utils {
    LogHelper
}

import java.io {
    IOException
}
import java.lang {
    JString=String
}
import java.util {
    ArrayList,
    HashMap
}

import org.xmlpull.v1 {
    XmlPullParserException,
    XmlPullParser
}

shared class PackageValidator(Context ctx) {

    value tag = LogHelper.makeLogTag(`PackageValidator`);

    function readValidCertificates(XmlResourceParser parser) {
        value validCertificates = HashMap<String,ArrayList<CallerInfo>>();
        try {
            variable Integer eventType = parser.next();
            while (eventType != XmlResourceParser.endDocument) {
                if (eventType == XmlResourceParser.startTag, parser.name.equals("signing_certificate")) {
                    XmlPullParser pullParser = parser;
                    value name = pullParser.getAttributeValue(null, "name");
                    value packageName = pullParser.getAttributeValue(null, "package");
                    value isRelease = parser.getAttributeBooleanValue(null, "release", false);
                    value certificate = JString(parser.nextText()).replaceAll("\\s|\\n", "");
                    value info = CallerInfo(name, packageName, isRelease);
                    if (exists infos = validCertificates.get(certificate)) {
                        infos.add(info);
                    }
                    else {
                        value newInfos = ArrayList<CallerInfo>();
                        newInfos.add(info);
                        validCertificates.put(certificate, newInfos);
                    }
//                    LogHelper.v(tag, "Adding allowed caller: ", info.name, " package=", info.packageName, " release=", info.release, " certificate=", certificate);
                }
                eventType = parser.next();
            }
        }
        catch (XmlPullParserException|IOException e) {
//            LogHelper.e(tag, e, "Could not read allowed callers from XML.");
        }
        return validCertificates;
    }

    value mValidCertificates = readValidCertificates(ctx.resources.getXml(R.Xml.allowed_media_browser_callers));

    function getPackageInfo(Context context, String pkgName) {
        try {
            return context.packageManager.getPackageInfo(pkgName, PackageManager.getSignatures);
        }
        catch (PackageManager.NameNotFoundException e) {
//            LogHelper.w(tag, e, "Package manager can't find package: ", pkgName);
            return null;
        }
    }

    shared Boolean isCallerAllowed(Context context, String callingPackage, Integer callingUid) {
        if (Process.systemUid == callingUid
            || Process.myUid() == callingUid
            || isPlatformSigned(context, callingPackage)) {
            return true;
        }

        if (exists packageInfo = getPackageInfo(context, callingPackage)) {
            if (packageInfo.signatures.size == 1) {
                value signature = Base64.encodeToString(packageInfo.signatures.get(0).toByteArray(), Base64.noWrap);
                if (exists validCallers = mValidCertificates.get(signature)) {
                    value expectedPackages = StringBuilder();
                    for (info in validCallers) {
                        if (callingPackage == info.packageName) {
//                        LogHelper.v(tag, "Valid caller: ", info.name, "  package=", info.packageName, " release=", info.release);
                            return true;
                        }
                        expectedPackages.append(info.packageName).appendCharacter(' ');
                    }
                    LogHelper.i(tag, "Caller has a valid certificate, but its package doesn't match any ", "expected package for the given certificate. Caller's package is ", callingPackage, ". Expected packages as defined in res/xml/allowed_media_browser_callers.xml are (", expectedPackages, "). This caller's certificate is: \n", signature);
                } else {
                    LogHelper.v(tag, "Signature for caller ", callingPackage, " is not valid: \n", signature);
                    if (mValidCertificates.empty) {
                        LogHelper.w(tag, "The list of valid certificates is empty. Either your file ", "res/xml/allowed_media_browser_callers.xml is empty or there was an error ", "while reading it. Check previous log messages.");
                    }
                }
            }
            else {
                LogHelper.w(tag, "Caller does not have exactly one signature certificate!");
            }
        }

        return false;

    }

    Boolean isPlatformSigned(Context context, String pkgName) {
        if (exists platformPackageInfo = getPackageInfo(context, "android"),
            exists platformSigs = platformPackageInfo.signatures,
            platformSigs.size > 0,
            exists clientPackageInfo = getPackageInfo(context, pkgName),
            exists clientsSigs = clientPackageInfo.signatures,
            clientsSigs.size > 0) {
            return platformPackageInfo.signatures.get(0)
                == clientPackageInfo.signatures.get(0);
        }
        else {
            return false;
        }
    }

}

class CallerInfo(shared String name, shared String packageName, shared Boolean release) {}