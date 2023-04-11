Input
```xml
<a>
    <b>bb</b>
</a>
```
```bash
$ echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/*' -t elem -n xx -v 1111
<?xml version="1.0"?>
<a>
  <xx>1111</xx>
  <b>bb</b>
</a>
```
```bash
$ echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/b' -t elem -n xx -v 1111
<?xml version="1.0"?>
<a>
  <xx>1111</xx>
  <b>bb</b>
</a>

```
```bash
$ echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/b' -t elem -n xx -v 1111
<?xml version="1.0"?>
<a>
  <xx>1111</xx>
  <b>bb</b>
</a>
```
```bash
$ echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/*' -t elem -n xx -v 1111
<?xml version="1.0"?>
<a>
  <xx>1111</xx>
  <b>bb</b>
</a>
```

    1  2023-03-08 13:49:49 echo '<a><b>bb</b></a>' | xmlstarlet 
    2  2023-03-08 13:50:00 echo '<a><b>bb</b></a>' | xmlstarlet sel a
    3  2023-03-08 13:50:12 echo '<a><b>bb</b></a>' | xmlstarlet sel -t a
    4  2023-03-08 13:50:50 echo '<a><b>bb</b></a>' | xmlstarlet sel '//a'
    5  2023-03-08 13:51:28 echo '<a><b>bb</b></a>' | xmlstarlet el
    6  2023-03-08 13:51:42 echo '<a><b>bb</b></a>' | xmlstarlet sel 'a/b'
    7  2023-03-08 13:54:02 echo '<a><b>bb</b></a>' | xmlstarlet ed 'a/b'
    8  2023-03-08 13:54:35 echo '<a><b>bb</b></a>' | xmlstarlet ed -t text -n 'a/b' -v cccc
    9  2023-03-08 13:55:05 echo '<a><b>bb</b></a>' | xmlstarlet ed  -n 'a/b' -v cccc
   10  2023-03-08 13:56:00 echo '<a><b>bb</b></a>' | xmlstarlet ed -t text -N 'a/b' -v cccc
   11  2023-03-08 13:56:07 echo '<a><b>bb</b></a>' | xmlstarlet ed -N 'a/b' -v cccc
   12  2023-03-08 13:57:03 echo '<a><b>bb</b></a>' | xmlstarlet ed -i -t text -N 'a/b' -v cccc
   13  2023-03-08 13:57:13 echo '<a><b>bb</b></a>' | xmlstarlet ed -i -t text -n 'a/b' -v cccc
   14  2023-03-08 13:57:36 echo '<a><b>bb</b></a>' | xmlstarlet ed -i -t text -n '//a/b' -v cccc
   15  2023-03-08 14:00:45 echo '<a><b>bb</b></a>' | xmlstarlet ed -i -t elem -n '//a/b' -v cccc
   16  2023-03-08 14:01:24 echo '<a><b>bb</b></a>' | xmlstarlet ed -t elem -i -n '//a/b' -v cccc
   17  2023-03-08 14:02:22 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a' -t elem -i -n b -v cccc
   18  2023-03-08 14:03:04 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a' -t elem -n b -v cccc
   19  2023-03-08 14:03:36 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/b' -t elem -n b -v cccc111
   20  2023-03-08 16:54:42 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/b' -t elem -n b -v ccc
   21  2023-03-08 17:00:09 echo '<a><b>bb</b></a>' | xmlstarlet sel -if '//a/b' -t elem -n b -v ccc
   22  2023-03-08 17:01:01 echo '<a><b>bb</b></a>' | xmlstarlet sel '//a/b'
   23  2023-03-08 17:01:12 echo '<a><b>bb</b></a>' | xmlstarlet sel '//a/b' -t attr
   24  2023-03-09 12:17:30 echo '<a><b>bb</b></a>' | xmlstarlet sel '//a/b' -t elem
   25  2023-03-09 12:17:42 xmlstarlet sel -
   26  2023-03-09 12:24:46 echo '<a><b>bb</b></a>' | xmlstarlet sel -t -v '//a/b' -t elem
   27  2023-03-09 12:24:51 echo '<a><b>bb</b></a>' | xmlstarlet sel -t -v '//a/b' 
   28  2023-03-09 12:25:07 echo '<a><b>bb</b></a>' | xmlstarlet sel -t -if -v '//a/b' 
   29  2023-03-09 12:26:10 echo '<a><b>bb</b></a>' | xmlstarlet sel -t -v '//a/b' 
   30  2023-03-09 12:26:20 echo '<a><b>bb</b></a>' | xmlstarlet sel -t -v '//a/bx' 
   31  2023-03-09 12:27:20 echo '<a><b>bb</b></a>' | xmlstarlet sel -t -v '//a/b' || xmlstarlet sel -t -v '//a/b'[C 
   32  2023-03-09 12:27:43 echo '<a><b>bb</b></a>' | xmlstarlet ed -u -v '//a/bx' 
   33  2023-03-09 12:28:06 echo '<a><b>bb</b></a>' | xmlstarlet ed -i -v '//a/bx' 
   34  2023-03-09 12:30:02 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/bx' -v 1111 
   35  2023-03-09 12:30:47 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/bx' -t elem -v 1111 
   36  2023-03-09 12:31:17 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/bx' -t elem -n xx -v 1111 
   
   37  2023-03-09 12:31:30 echo '<a><b>bb</b></a>' | xmlstarlet ed -i '//a/b' -t elem -n xx -v 1111 
