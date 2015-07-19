ios-resource-tool
=================

`ios-resource-tool` is a collection of ruby scripts to help you work with iOS resources:

+ Export Android `<string>`, `<string-array>`, `<plurals>` to iOS
+ Generate CSV report if requested
+ Generate R.swift to mimic Android R.java
+ Generate R+assets.swift to access .xcassets

Why use this tool?
------------------

If you are doing cross platform development, then you known it is painful to do
localization strings management, as iOS and Android are using different format.

Personally I find Android resource management is much better than iOS's, and
the string definition is much clear with Android, especially for array and plurals.
That's why I need a tool to do strings conversion from Android to iOS.

There are many tools, even some on-line services to solve this problem. But I find
they are more or less having some shortcomings, mostly:

+ no `<string-array>` support
+ no `<plurals>` support
+ no type-safe way to access resource for iOS development

I want a tool to do these all, and can do it in batch, so I can put it into build script
if needed. Thus why I write this script by myself.

Supported Android resource types
--------------------------------

The following Android resource types are supported by this tool:

Android xml tag | iOS file
----------------|-----------
string          | Generate to Localizable.strings
string-array    | Generate to LocalizableArray.strings
plurals         | Generate to Localizable.stringsdict

For every language, Android side may have multiple .xml files, all will be merged into
single file on iOS. The iOS file will be put into proper language directory, such as Base.lproj,
zh-Hant.lproj, etc...

Import strings from Android
---------------------------

Take the following Android project for example:

````
~/android_app
+-- src/
+-- res/
    +-- values/
    |   +-- strings.xml
    |   +-- strings_about.xml
    |   +-- strings_menu.xml
    |   +-- arrays.xml
    |   +-- plurals.xml
    +-- values-zh-rTW/
        +-- strings.xml
        +-- plurals.xml
````

And iOS project before running the tool:

````
~/ios_app
+-- src/
+-- res/
````

Then you can run the tool for ios_app:

````
ruby ios-strings.rb --in=~/android_app/res --out=~/ios_app/res
````

And the iOS project will look like

````
~/ios_app
+-- src/
+-- res/
    +-- R.swift
    +-- Base.lproj
    |   +-- Localizable.strings
    |   +-- LocalizableArray.strings
    |   +-- Localizable.stringsdict
    +-- zh-Hant.lproj
        +-- Localizable.strings
        +-- LocalizableArray.strings
        +-- Localizable.stringsdict
````

Type-safe access to strings
---------------------------

The tools generate a `R.swift` that mimic Android `R.java`, the generated code is type-safe and IDE friendly:

The generated R.swift looks like:
````swift
struct R {
    enum string : String {
        case btn_ok
        ...
    }
    enum array : String {
        case menu_list
        ...
    }
    enum plurals : String {
        case item_count
        ...
    }
}
````

swift expression        | swift type | Usage
------------------------|------------|-------
R.string.btn_ok         | R.string   | enum case, you can get the key string by .rawValue
R.string.btn_ok^        | String     | To get the localized string
R.array.menu_list       | R.array    | enum case, you can get the key string by .rawValue
R.array.menu_list^      | [String]   | To get the localized string array
R.array.menu_list[3]    | String     | To get 3rd item of the localized string array
R.plurals.item_count    | R.plurals  | enum case, you can get the key string by .rawValue
R.plurals.item_count[5] | String     | To get the localized string with quantity 5

The ^ and [] operator for R.swift are overloaded to provide access to the strings.

Generate CSV report
-------------------

The `ios-strings.rb` can also export resources to one CSV file, for review or other purpose, please try:

````
ruby ios-strings.rb --in=~/android_app/res --report=report.csv
````

Type-safe access to assets
--------------------------

Another tool `ios-assets.rb` will generate `R+assets.swift` as extension to `R.swift`, that provides type-safe and IDE
friendly access to the image assets. To run the tool:

````
ruby ios-assets.rb --res=~/ios_app/res
````

The generated R+assets.swift looks like:
```` swift
extension R {
    enum image : String {
        case icon_logo
        ...
    }
}
````

swift expression        | swift type | Usage
------------------------|------------|-------
R.image.icon_logo       | R.image    | enum case, you can get the key string by .rawValue
R.image.icon_logo^      | UIImage    | To get the image from assets

The postfix ^ operator for R+assets.swift are overloaded to provide access to the assets.
