# FLM
## INSTALATION
1. Install PostgreSQL 9.4+ database.
2. Install all packages from setup/packages.sh
3. Create database and user.
4. Execute the following sql script: \i setup/db/db.sql in your database. The script will create needed tables.

Example Apache2 configuration under mod_perl, you need to replace < DIR TO PROJECT > AND < PORT > with yours.
If you do not have installed mod_perl you need to execute the following command apt-get install libapache2-mod-perl2.

```apache
Listen < PORT > # Listen 5555

<VirtualHost  _default_:< PORT >>
    PerlWarn On
    PerlOptions +Parent -InheritSwitches

    <Files ~ "\.pl$">
           SetHandler perl-script
           PerlResponseHandler ModPerl::RegistryPrefork
           Options +ExecCGI
           PerlSendHeader On
        </Files>

    PerlSwitches -I< DIR TO PROJECT >/lib/perl -I< DIR TO PROJECT >/common/lib/perl

    <Directory "< DIR TO PROJECT >/www-root" >
        Order deny,allow
        Deny from all
        Allow from all
        DirectoryIndex app.pl
    </directory>

    Alias /api < DIR TO PROJECT >/www-root/app.pl
    Alias / < DIR TO PROJECT >/www-root/
</VirtualHost>
```

Your application URL: [http://< host >:< port >/index.html]()
Your API URL: [http://< host >:< port >/api]()

## CONFIGURATION
1. Go to lib/perl/FLM/ directory. Copy Config.pm.Sample with new file name Config.pm in the same dir and open the file with a text editor of your choice.
2. Setup db credentials with yours:
* $dbi_dbName - Name of the dabase
* $dbi_dbHost - DB Host
* $dbi_dbUser - DB User
* $dbi_dbAuth - DB Password
* $dbi_dbPort - DB Port
3. Setup directory where files will be stored:
* $FILES_DIR
4. Play with other configurations:
* $FORBIDDEN_FILE_EXT - Forbidden file types. The check is by file extension and file meta data. 
* $MAX_FILE_SIZE - Max allowed file size in bytes for file.
* $MAX_UPLOADED_FILES - Max allowed number of uploaded files.

## MODULES
#### FLM::Common::DBIHelper
Provides some helper functionality for DBI.
```perl 
FLM::Common::DBIHelper->connect($params); #DBI PG connection without transactions

FLM::Common::DBIHelper->connect_transact($params); #DBI PG connection with transactions with default DBI isolation level SERIALIZABLE

$dbi->InsertInto($table_name, {col => $val}); #Generate and execute Insert query from hashref. Returns inserted row as hashref.
```

#### FLM::Common::Errors

##### Synopsis
```perl
ASSERT($cond, "Message", "Code");
ASSERT_PEER($cond, "Message", "Code");
ASSERT_USER($cond, "Message", "Code");
TRACE("Param", $hashref, $arrref, $string); #Print on STDERR all passed params, accepts list of params. Uses Data::Dumper so there is no problem to pass ARRAYREF or HASHREF as parameters.
```
Provides three types of exceptions and one trace function. Exceptions methods works like asserts i.e. accepts as a parameter some condition if condition is false, throws a exception.
The exceptions are three types:
1. SYSERR - in most cases means temporary error
2. PEERERR - protocol error or invalid params, this exception type must be used for validating API input params.
3. USERERR - end user error for example "Reached max file size"

All methods in this module are static.

#### FLM::App
##### API
Handler method is a API entry point.
Supported API methods are in global hashref `$commands`.
##### DataBase
Uses FLM::Common::DBIHelper->connect_transact so everything is in transaction, isolation level SERIALIZABLE.
##### Exceptions
There is three type of exceptions: SYSERR, PEERERR, USERERR provied from FLM::Common:Errors module. Exceptions are processed in the Handler method.
##### Other information
If setting `$FORBIDDEN_FILE_EXT` is filled the application will check the file by extension and meta data, so the application can validate file which is without extension in the name.


## API DOCUMENTATION
Arguments can be passed as GET or POST params, but not a mix. If the HTTP status is 200 OK the response will contains attachment with file name and mime type or JSON object, which will always contain a top-level JSON object `status`. Status object will always contain property `status`, indicating success or failure. 

On success `status` will be `ok`.
Example:
```json
{
    "status": {
        "status":"ok"
    },
    "result": {...}
}
```

On failure `status` will be `peer_err`, `sys_err` or `user_err`. Also top-level `status` object contains properties `code` and `msg`. `code` is a short error code. `msg` is a error message which can be shown to the end user.

##### peer_error
This type of errors means protocol error or invalid request. The system can not recover after retry.
Example:
```json
{
    "status":{
        "code":"PEER01",
        "status":"peer_err",
        "msg":"Client system error!"
    }
}
```

##### sys_err
This type of errors most often means temporary errors and in most cases the system will recover after retry.
Example:
```json
{
    "status":{
        "status":"sys_err",
        "code":"SYS000",
        "msg":"Something went wrong, please try again!"
    }
}
```

##### user_err
This type of errors means that the error is in the end user. For example, reached file size limit or reached max number of allowed uploaded files.
Example:
```json
{
    "status":{
        "code":"UI05",
        "msg":"Maximum number of allowed uploaded files is 4",
        "status":"user_err"
    }
}
```

#### API RESPONSE OBJECTS
##### file_object
| Property | Type | Required | Description |
| ------ | ------ | ------ | ------ |
| id | int | Required | File ID in the system |
| name | str | Required | FIle name | 
| inserted_at | timestamp | Required | File creation date in the system |
| meta_data | meta_data_object | Required | File meta data |

##### meta_data_object
| Property | Type | Required | Description |
| ------ | ------ | ------ | ------ |
| ext | str | Optional | File extension |
| mime_type | str | Optional | File MIME Type |
| file_ctime | unix timestamp | Required | File creation time in the system | 
| file_mtime | unix timestamp | Required | File modification time in the system |
| file_atime | unix timestamp | Required | File access time in the system |
| file_size_bytes | int | Required | File size |


#### API METHODS
##### upload_file
###### Input params
| Param | Example | Required | Description |
| ------ | ------ | ------ | ------ |
| method | upload_file | Required | |
| file | ... | Required | File contents via multipart/form-data |

###### Response
Array of **file_object**
Example:
```json
{
    "status":{
        "status":"ok"
    },
    "result":[
        {
            "id":53,
            "inserted_at":"2017-08-21 20:12:19.728053",
            "meta_data":{
                "ext":".jpg",
                "file_ctime":1503335535,
                "file_mtime":1503335535,
                "mime_type":"image/jpeg",
                "file_atime":1503335535,
                "file_size_bytes":324717
            },
            "name":"20771674_499139963783051_1849452675_o (28).jpg"
        }
    ]
}
```

###### CURL Example
```curl
curl -X POST -F file=@apple.png -F method="upload_file" http://<YOUR_API_URL>
```


##### get_files_list
###### Input params
| Param | Example | Required | Description |
| ------ | ------ | ------ | ------ |
| method | get_files_list | Required | |

###### Response
Array of **file_object**
Example:
```json
{
  "status": {
    "status": "ok"
  },
  "result": [
    {
      "name": "Apple-Logo-Png-Download (1).png",
      "id": 13,
      "inserted_at": "2017-08-20 11:09:35",
      "meta_data": {
        "file_ctime": 1503227374,
        "ext": ".png",
        "file_mtime": 1503227374,
        "mime_type": "image/png",
        "file_atime": 1503227374,
        "file_size_bytes": 929419
      }
    },
    {
      "meta_data": {
        "file_ctime": 1503235244,
        "ext": ".jpg",
        "mime_type": "image/jpeg",
        "file_mtime": 1503235244,
        "file_atime": 1503235244,
        "file_size_bytes": 324717
      },
      "inserted_at": "2017-08-20 13:20:45",
      "id": 15,
      "name": "20771674_499139963783051_1849452675_o.jpg"
    }
  ]
}
```

###### CURL Example
```curl
curl -X GET  http://< YOUR API URL >?method=get_files_list
```


##### get_file_data
###### Input params
| Param | Example | Required | Description |
| ------ | ------ | ------ | ------ |
| method | get_file_data | Required | |
| file_id | 13 | Required | File id |

###### Response
**file_object**
Example:
```json
{
  "status": {
    "status": "ok"
  },
  "result": {
    "name": "Apple-Logo-Png-Download (1).png",
    "meta_data": {
      "mime_type": "image/png",
      "file_mtime": 1503227374,
      "file_ctime": 1503227374,
      "ext": ".png",
      "file_size_bytes": 929419,
      "file_atime": 1503227374
    },
    "id": 13,
    "inserted_at": "2017-08-20 11:09:35"
  }
}
```

###### CURL Example
```curl
curl -X GET "http://< YOUR API URL >?method=get_file_data&file_id=15"
```


##### delete_file
###### Input params
| Param | Example | Required | Description |
| ------ | ------ | ------ | ------ |
| method | delete_file | Required | |
| file_id | 13 | Required | File id |

###### Response
**file_object**
Example:
```json
{
  "status": {
    "status": "ok"
  },
  "result": {
    "meta_data": {
      "file_mtime": 1503227374,
      "ext": ".png",
      "file_atime": 1503227374,
      "file_size_bytes": 929419,
      "mime_type": "image/png",
      "file_ctime": 1503227374
    },
    "id": 13,
    "inserted_at": "2017-08-20 11:09:34.625098",
    "name": "Apple-Logo-Png-Download (1).png"
  }
}
```

###### CURL Example
```curl
curl -X GET "http://< YOUR API URL >?method=delete_file&file_id=15"
```



##### download_file
###### Input params
| Param | Example | Required | Description |
| ------ | ------ | ------ | ------ |
| method | download_file | Required | |
| file_id | 13 | Required | File id |

###### Response
```text
atachment with file name and mime type in http headers.
```

###### CURL Example
```curl
curl -X GET "http://< YOUR API URL >?method=download_file&file_id=53"
```

