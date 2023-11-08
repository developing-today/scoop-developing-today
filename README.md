# scoop-developing-today

A [Scoop](http://scoop.sh) bucket of useful [developing-today](https://github.com/developing-today/) utilities.

To make it easy to install apps from this bucket, run:

```
scoop bucket add developing-today https://github.com/developing-today/scoop-developing-today
```
## SHA check?

developing-today includes a `checksums.txt`, `checksums.txt.pem`, `checksums.txt.sig` files. These could be used to automatically check the hash of the downloaded file. As-is, we are not validating the hash and are relying on the github release being valid.


## Why does this exist?

For an app to be acceptable for the main bucket, it should be:

* open source
* a command-line program
* the latest stable version of the program
* reasonably well-known and widely used

The "extras" bucket has more relaxed requirements, so it's a good place to put anything that doesn't quite fit in the main bucket.

The "developing-today" bucket is specifically for the utilities found on the developing-today website which haven't made it into the main bucket, _yet_.
