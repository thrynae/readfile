[![View readfile on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/68780-readfile)

If you want to read a (text) file with Matlab, you need to know what encoding it is: UTF-8 (the 'modern' standard) or ANSI (US-ASCII, the 'old' standard). If you have files you want to read automatically, where you don't necessarily know the encoding you would have to guess. This will sometimes result in strange text that you only notice 3 or 4 steps later.

This function takes care of that problem by providing a single way of reading a file. It preserves leading and trailing spaces, it preserves empty lines, and it can handle both UTF-8 files and ANSI files. Note that although the encoding should be specified in a special leading bit, it is not possible to read this with Matlab nor is it actually guaranteed to be present. It is therefore possible that a file is read with the wrong encoding, although this should be a very rare occurrence.

It is also possible to enter the file name as a URL. In that case this function will download the file to the temporary directory, read it, and delete it. If that fails, webread/urlread will be used to read the file as a char array, although that may limit which characters can be read depending on the Matlab/Octave release and OS.

This function support most syntax options that the readlines function (introduced in R2020b) supports. It even has a switch to reproduce a bug with reading most emoji. In general cellstr(readlines(___)) should provide equivalent results.

Licence: CC by-nc-sa 4.0