#!/usr/bin/env ruby
#
# https://github.com/SteveKChiu/ios-res-tool
#
# Copyright 2015, Steve K. Chiu <steve.k.chiu@gmail.com>
#
# What it does is to read Andrord resources and translate it into iOS resources:
#
# + string, string-array and plurals are supported
# + values-zh-rTW will be translated into zh-Hant.lproj
# + values-zh-rHK will be translated into zh-Hant_HK.lproj
# + values-zh-rCN will be translated into zh-Hans.lproj
# + string format %s will be translated into %@
# + string format %,d will be translated into %d
# + type-safe and Xcode friendly R.swift
# + CSV report
#
# The MIT License (http://www.opensource.org/licenses/mit-license.php)
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#

require 'fileutils'
require 'pathname'
require 'rexml/document'
require 'optparse'
require 'csv'

ARGV << '--help' if ARGV.empty?

options = {
  :copy_base => false,
  :import => [],
  :export => [],
}

OptionParser.new { |opts|
  opts.banner = "Usage: ios-strings.rb [options]"

  opts.on("--import-android=DIR", "Import from Andrord resources directory") { |v|
    options[:import] << { :type => 'android', :path => v }
  }

  opts.on("--import-ios=DIR", "Import from iOS resources directory") { |v|
    options[:import] << { :type => 'ios', :path => v }
    options[:ios_path] = v
  }

  opts.on("--import-csv=FILE", "Import from CSV file") { |v|
    options[:import] << { :type => 'csv', :path => v }
  }

  opts.on("--export-ios=DIR", "Export to iOS resources directory") { |v|
    options[:export] << { :type => 'ios', :path => v }
    options[:ios_path] = v
  }

  opts.on("--export-csv=FILE", "Export to CSV file") { |v|
    options[:export] << { :type => 'csv', :path => v }
  }

  opts.on("--export-swift", "Generate R.swift, require import or export iOS options") {
    options[:export] << { :type => 'swift', :path => options[:ios_path] }
  }

  opts.on("--copy-base=LOCALE", "Copy base resource to the specified locale") { |v|
    options[:copy_base] = v
  }

  opts.on_tail("--help", "Show this message") {
    puts opts
    exit
  }
}.parse!

$locales = {}
$strings_keys = {}
$arrays_keys = {}
$plurals_keys = {}

def import_android_string(str)
  str.gsub!(/^"(.*)"$/, '\1')
  str.gsub!(/(%(\d\$)?)s/, '\1@')
  str.gsub!(/(%(\d\$)?),d/, '\1d')
  str.gsub!(/\\"/, '"')
  return str
end

def import_android(import_path)
  Pathname.glob(import_path + 'values*/').each { |values_path|
    name = values_path.basename.to_s

    if name == 'values'
      locale = "Base"
    else
      locale = name.gsub(/^values-(.+)$/, '\1').gsub(/-r/, '-')
      if locale == 'zh-TW'
        locale = 'zh-Hant'
      elsif locale == 'zh-HK'
        locale = 'zh-Hant_HK'
      elsif locale == 'zh-CN'
        locale = 'zh-Hans'
      end
    end

    values = {
      :strings => {},
      :arrays => {},
      :plurals => {},
    }

    Pathname.glob(values_path + '*.xml').each { |xml_path|
      puts "xml: #{xml_path}"

      xml = File.read xml_path.to_s
      doc = REXML::Document.new(xml)

      doc.elements.each('resources/string') { |str|
        next if str.attributes['translatable'] == 'false'

        key = str.attributes['name']
        puts "string: #{key}"

        until not str.has_elements?
          str.each_element { |astr|
            str = astr
          }
        end

        next if not str.text
        $strings_keys[key] = true
        values[:strings][key] = import_android_string(str.text)
      }

      doc.elements.each('resources/string-array') { |arr|
        next if arr.attributes['translatable'] == 'false'

        key = arr.attributes['name']
        puts "string-array: #{key}"

        arr_items = []
        arr.elements.each { |e|
          if e.name == 'item'
            arr_items << import_android_string(e.text)
          end
        }

        if not arr_items.empty?
          $arrays_keys[key] = true
          values[:arrays][key] = arr_items
        end
      }

      doc.elements.each('resources/plurals') { |plu|
        next if plu.attributes['translatable'] == 'false'

        key = plu.attributes['name']
        puts "plurals: #{key}"

        plu_items = []
        plu.elements.each { |e|
          if e.name == 'item'
            qty = e.attributes['quantity']
            value = import_android_string(e.text)
            plu_items << { :qty => qty, :value => value }
          end
        }

        if not plu_items.empty?
          $plurals_keys[key] = true
          values[:plurals][key] = plu_items
        end
      }

      if not values[:strings].empty? or not values[:arrays].empty? or not values[:plurals].empty?
        map = $locales[locale]
        if not map
          $locales[locale] = values
        else
          map[:strings].merge!(values[:strings])
          map[:arrays].merge!(values[:arrays])
          map[:plurals].merge!(values[:plurals])
        end
      end
    }
  }
end

def parse_ios_token(line, sep)
  n = 0
  in_value = false
  in_quote = false
  in_escape = false
  value = ""

  for ch in line.chars
     n += 1

    if not in_value
      if ch == "\""
        in_quote = true
        in_value = true
      elsif ch != " " and ch != "\t" and ch != sep
        in_value = true
        value << ch
      end
      next
    end

    if in_escape
      value << ch
      in_escape = false
    elsif ch == "\\"
      in_escape = true
    elsif in_quote
      if ch == "\""
        break
      else
        value << ch
      end
    else
      if ch == " " or ch == "\t" or ch == sep
        n -= 1
        break
      else
        value << ch
      end
    end
  end

  return value, line[n..-1]
end

def import_ios(import_path)
  Pathname.glob(import_path + '**/*.lproj/').each { |lproj_path|
    name = lproj_path.basename.to_s
    locale = name.gsub(/^(.+)\.lproj$/, '\1')

    values = {
      :strings => {},
      :arrays => {},
      :plurals => {},
    }

    Pathname.glob(lproj_path + '*.strings').each { |strings_path|
      puts "strings: #{strings_path}"

      IO.foreach(strings_path.to_s, mode: 'r:bom|utf-8') { |line|
        line.strip!
        next if line.start_with?('#')

        key, line = parse_ios_token(line, "=")
        line.strip!

        next if not line.start_with?("=")
        line.slice!(0)

        value, line = parse_ios_token(line, ";")

        $strings_keys[key] = true
        values[:strings][key] = value
      }

      if not values[:strings].empty? or not values[:arrays].empty? or not values[:plurals].empty?
        map = $locales[locale]
        if not map
          $locales[locale] = values
        else
          map[:strings].merge!(values[:strings])
          map[:arrays].merge!(values[:arrays])
          map[:plurals].merge!(values[:plurals])
        end
      end
    }
  }
end

def import_csv(csv_path)
  is_first = true
  locales_keys = []

  CSV.foreach(csv_path.to_s) { |row|
    if is_first
      row.delete_at(0)
      row.delete_at(row.size - 1) if not row.last
      locales_keys = row
      is_first = false
      next
    end

    key = row[0]
    type = nil
    row.delete_at(0)

    if not type
      r = key.match(/^(.*)\.(\d+)/)
      if r
        type = :arrays
        key = r[1]
        part = r[2].to_i
      end
    end

    if not type
      r = key.match(/^(.*)\.([a-z]+)/)
      if r
        type = :plurals
        key = r[1]
        part = r[2]
      end
    end

    if not type
      type = :strings
    end

    for idx in 0...locales_keys.size
      locale = locales_keys[idx]

      if not $locales[locale]
        $locales[locale] = {
          :strings => {},
          :arrays => {},
          :plurals => {},
        }
      end

      values = $locales[locale][type]
      value = row[idx]
      next if not value

      if type == :strings
        values[key] = value
        $strings_keys[key] = true
      elsif type == :arrays
        arr = values[key]
        if not arr
          arr = []
          values[key] = arr
        end
        arr[part] = value
        $arrays_keys[key] = true
      elsif type == :plurals
        plu = values[key]
        if not plu
          plu = []
          values[key] = plu
        end
        plu << { :qty => part, :value => value }
        $plurals_keys[key] = true
      end
    end
  }
end

def ensure_order(array, order)
    out = []
    order.each { |e|
      out << e if array.include?(e)
    }
    out += array.sort - order
    return out
end

def lookup_locales(locale, type, key)
    while true
      values = $locales[locale]
      if values
        value = values[type][key]
        return value if value
      end

      break if locale == 'Base'

      r = locale.match(/^(.*)-[^-]+$/)
      locale = r ? r[1] : "Base"
    end
    return nil
end

def lookup_string_ref(locale, str)
  old = str
  while str
    r = str.match(/^@string\/(.*)$/)
    break if not r
    str = lookup_locales(locale, :strings, r[1])
  end
  return str if str
  return old
end

def export_ios_string(locale, str)
  str = lookup_string_ref(locale, str)
  str.gsub!(/"/, '\\"')
  return str
end

def export_ios(res_path, locale)
  locale_path = res_path + "#{locale}.lproj"
  FileUtils.mkdir_p(locale_path) unless File.directory?(locale_path)

  if not $strings_keys.empty?
    strings_path = locale_path + 'Localizable.strings'
    strings_path.delete if strings_path.exist?

    File.open(strings_path, 'wb') { |f|
      f.write "\xef\xbb\xbf"

      $strings_keys.each { |key|
        value = lookup_locales(locale, :strings, key)
        value = export_ios_string(locale, value)
        f.write "\"#{key}\" = \"#{value}\";\n"
      }
    }
  end

  if not $arrays_keys.empty?
    arrays_path = locale_path + 'LocalizableArray.strings'
    arrays_path.delete if arrays_path.exist?

    File.open(arrays_path, 'wb') { |f|
      f.write "\xef\xbb\xbf"

      $arrays_keys.each { |key|
        arr = lookup_locales(locale, :arrays, key)

        f.write "\"#{key}\" = (\n"
        arr.each { |value|
          value = export_ios_string(locale, value)
          f.write "    \"#{value}\",\n"
        }
        f.write ");\n\n"
      }
    }
  end

  if not $plurals_keys.empty?
    plurals_path = locale_path + 'Localizable.stringsdict'
    plurals_path.delete if plurals_path.exist?

    File.open(plurals_path, 'wb') { |f|
      f.write "\xef\xbb\xbf"
      f.write "<plist version=\"1.0\">\n"
      f.write "<dict>\n\n"

      $plurals_keys.each { |key|
        plu = lookup_locales(locale, :plurals, key)

        f.write "<key>#{key}</key>\n"
        f.write "<dict>\n"
        f.write "    <key>NSStringLocalizedFormatKey</key>\n"
        f.write "    <string>%\#@x@</string>\n"
        f.write "    <key>x</key>\n"
        f.write "    <dict>\n"
        f.write "        <key>NSStringFormatSpecTypeKey</key>\n"
        f.write "        <string>NSStringPluralRuleType</string>\n"
        f.write "        <key>NSStringFormatValueTypeKey</key>\n"
        f.write "        <string>d</string>\n"

        plu.each { |e|
          qty = e[:qty]
          value = export_ios_string(locale, e[:value])
          value = value.gsub(/%\d\$,?d/, '%d')
          f.write "        <key>#{qty}</key>\n"
          f.write "        <string>#{value}</string>\n"
        }

        f.write "    </dict>\n"
        f.write "</dict>\n\n"
      }

      f.write "</dict>\n"
      f.write "</plist>\n"
    }
  end
end

def export_swift(res_path)
  swift_path = res_path + "R.swift"
  swift_path.delete if swift_path.exist?

  File.open(swift_path, 'wb') { |f|
    f.write "// THIS FILE IS GENERATED BY TOOL, PLEASE DO NOT EDIT!\n\n"
    f.write "import Foundation\n\n"
    f.write "struct R {\n\n"

    if not $strings_keys.empty?
      f.write "    enum string : String {\n"
      $strings_keys.each { |key|
        value = lookup_locales('Base', :strings, key)
        value = export_ios_string('Base', value)
        f.write "        /// #{value}\n"
        f.write "        case #{key}\n"
      }
      f.write "    }\n\n"
    end

    if not $arrays_keys.empty?
      f.write "    enum array : String {\n"
      $arrays_keys.each { |key|
        f.write "        case #{key}\n"
      }
      f.write "\n"
      f.write "        subscript(index: Int) -> String {\n"
      f.write "            return R.arrays[self.rawValue]![index]\n"
      f.write "        }\n"
      f.write "    }\n\n"
      f.write "    fileprivate static var arrays: [String : [String]] = {\n"
      f.write "        let path = Bundle.main.path(forResource: \"LocalizableArray\", ofType: \"strings\")!\n"
      f.write "        let dict = NSDictionary(contentsOfFile: path)!\n"
      f.write "        var map = [String : [String]]()\n"
      f.write "        for (k, v) in dict {\n"
      f.write "            let list = v as! [String]\n"
      f.write "            map[k as! String] = list\n"
      f.write "        }\n"
      f.write "        return map\n"
      f.write "    }()\n\n"
    end

    if not $plurals_keys.empty?
      f.write "    enum plurals : String {\n"
      $plurals_keys.each { |key|
        f.write "        case #{key}\n"
      }
      f.write "\n"
      f.write "        subscript(quantity: Int) -> String {\n"
      f.write "            return String.localizedStringWithFormat(NSLocalizedString(self.rawValue, comment: \"\"), quantity)\n"
      f.write "        }\n"
      f.write "    }\n\n"
    end

    f.write "}\n\n"

    if not $strings_keys.empty? or not $arrays_keys.empty?
      f.write "postfix operator ^\n\n"
    end

    if not $strings_keys.empty?
      f.write "postfix func ^ (key: R.string) -> String {\n"
      f.write "    return NSLocalizedString(key.rawValue, comment: \"\")\n"
      f.write "}\n\n"
    end

    if not $arrays_keys.empty?
      f.write "postfix func ^ (key: R.array) -> [String] {\n"
      f.write "    return R.arrays[key.rawValue]!\n"
      f.write "}\n\n"
    end
  }
end

def export_csv_string(locale, str)
  str = lookup_string_ref(locale, str)
  str.gsub!(/^"(.*)"$/, '\1')
  return '"' + str.gsub(/"/, '""') + '"'
end

def export_csv(csv_path)
  csv_path.delete if csv_path.exist?

  locale_keys = ensure_order($locales.keys, ['Base', 'en'])

  File.open(csv_path, 'wb') { |f|
    f.write "\xef\xbb\xbf"

    f.write "ID,"
    locale_keys.each { |locale|
      f.write "#{locale},"
    }
    f.write "\n"

    $strings_keys.each { |key|
      f.write "#{key},"
      locale_keys.each { |locale|
        value = lookup_locales(locale, :strings, key)
        value = "" if not value
        value = export_csv_string(locale, value)
        f.write "#{value},"
      }
      f.write "\n"
    }

    $arrays_keys.each { |key|
      max_size = 0
      locale_keys.each { |locale|
        arr = lookup_locales(locale, :arrays, key)
        max_size = arr.size if arr and arr.size > max_size
      }

      for idx in 1..max_size
        f.write "#{key}.#{idx},"
        locale_keys.each { |locale|
          arr = lookup_locales(locale, :arrays, key)
          value = (arr and idx <= arr.size) ? arr[idx-1] : ""
          value = export_csv_string(locale, value)
          f.write "#{value},"
        }
        f.write "\n"
      end
    }

    $plurals_keys.each { |key|
      qtys = {}
      locale_keys.each { |locale|
        plu = lookup_locales(locale, :plurals, key)
        next if not plu
        plu.each { |e|
          qtys[e[:qty]] = true
        }
      }

      qtys = ensure_order(qtys.keys, ['zero', 'one', 'two', 'few', 'many', 'other'])

      qtys.each { |qty|
        f.write "#{key}.#{qty},"
        locale_keys.each { |locale|
          plu = lookup_locales(locale, :plurals, key)
          plu = {} if not plu
          found = false

          plu.each { |e|
            if qty == e[:qty]
              found = true
              value = export_csv_string(locale, e[:value])
              f.write "#{value},"
              break
            end
          }

          if not found
            f.write ","
          end
        }
        f.write "\n"
      }
    }
  }
end

import_list = options[:import]
export_list = options[:export]

if not import_list.empty?
  import_list.each { |e|
    type = e[:type]
    import_path = Pathname.new(File.expand_path(e[:path]))

    unless import_path.exist?
      puts "Error! import directory not found: #{import_path}"
      exit
    end

    if type == 'android'
      import_android(import_path)
    elsif type == 'ios'
      import_ios(import_path)
    elsif type == 'csv'
      import_csv(import_path)
    end
  }
else
  puts "Error! you have to use one of the import options"
  exit
end

if $locales.empty?
  puts "Error! no resources found"
  exit
end

$strings_keys = $strings_keys.keys.sort
$arrays_keys = $arrays_keys.keys.sort
$plurals_keys = $plurals_keys.keys.sort

if options[:copy_base]
  $locales[options[:copy_base]] = $locales['Base']
end

if not export_list.empty?
  export_list.each { |e|
    type = e[:type]
    export_path = Pathname.new(File.expand_path(e[:path]))

    if type == 'ios'
      $locales.keys.each { |locale|
        export_ios(export_path, locale)
      }
    elsif type == 'swift'
      export_swift(export_path)
    elsif type == 'csv'
      export_csv(export_path)
    end
  }
else
  puts "Error! you have to use one of the export options"
  exit
end
