function data=readfile(filename)
%Read a UTF-8 or ANSI (US-ASCII) file
%
% Syntax:
%    data=readfile(filename)
%    filename: char array with either relative or absolute path, or a URL
%    data: n-by-1 cell (1 cell per line in the file, even empty lines)
%
% This function is aimed at providing a reliable method of reading a file. The backbone of this
% function is the fileread function. Further processing is done to attempt to detect if the file is
% UTF-8 or not, apply the transcoding and returning the file as an n-by-1 cell array for files with
% n lines.
%
% The test for being UTF-8 can fail. For files with chars in the 128:255 range, the test will often
% determine the encoding correctly, but it might fail. Online files are much more limited than
% offline files. To avoid this the files are downloaded to tempdir() and deleted after reading. 
%
% In Octave there is poor to no support for chars above 255. This has to do with the way Octave
% runs: it stores chars in a single byte. This limits what Octave can do regardless of OS. There
% are plans to extent the support, but this appears to be very far down the priority list, since it
% requires a lot of explicit rewriting. Even the current support for 128-255 chars seems to be 'by
% accident'. (Note that this paragraph was true in early 2020, so a big update to Octave may have
% added support by now. Although, don't hold your breath.)
%
%  _______________________________________________________________________
% | Compatibility | Windows 10  | Ubuntu 20.04 LTS | MacOS 10.15 Catalina |
% |---------------|-------------|------------------|----------------------|
% | ML R2020a     |  works      |  not tested      |  not tested          |
% | ML R2018a     |  works      |  partial #3      |  not tested          |
% | ML R2015a     |  works      |  partial #3      |  not tested          |
% | ML R2011a     |  works      |  partial #3      |  not tested          |
% | ML 6.5 (R13)  |  partial #2 |  not tested      |  not tested          |
% | Octave 5.2.0  |  partial #1 |  partial #1      |  not tested          |
% | Octave 4.4.1  |  partial #1 |  not tested      |  partial #1          |
% """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
% note #1: no support for char>255 (which are likely converted to 0)
% note #2: - no support for char>255 ANSI (unpredictable output)
%          - online (without download): could fail for files that aren't ANSI<256
% note #3: ANSI>127 chars are converted to 65533
%
% Version: 2.0.2
% Date:    2020-09-05
% Author:  H.J. Wisselink
% Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 )
% Email = 'h_j_wisselink*alumnus_utwente_nl';
% Real_email = regexprep(Email,{'*','_'},{'@','.'})

% Tested with 3 files with the following chars:
% list_of_chars_file1=[...
%     0032:0035 0037 0039:0042 0044:0059 0061 0063 0065:0091 0093 0096:0122 0160 0171 0173 0183 ...
%     0187:0189 0191:0193 0196 0200:0203 0205 0207 0209 0211 0212 0218 0224:0226 0228 0230:0235 ...
%     0237:0239 0241:0244 0246 0249:0253 8211 8212 8216:8218 8220:8222 8226 8230];
% list_of_chars_file2=[32:126 160:255 32 32 32];
% list_of_chars_file3=[...
%     0032:0126 0161:0163 0165 0167:0172 0174:0187 0191:0214 0216:0275 0278:0289 0292 0293 0295 ...
%     0298 0299 0304 0305 0308 0309 0313 0314 0317 0318 0321:0324 0327 0328 0336:0341 0344:0357 ...
%     0362:0369 0376:0382 0913:0929 0931:0974 0977 0984:0989 0991:0993 8211 8212 8216:8222 8224 ...
%     8225 8226 8230 8240 8249 8250 8260 8353 8356 8358 8361 8363 8364 8370 8482];

persistent CPwin2UTF8 origin target legacy isOctave runtimename
if isempty(CPwin2UTF8)
    CPwin2UTF8=[338 140;339 156;352 138;353 154;376 159;381 142;382 158;402 131;710 136;732 152;...
        8211 150;8212 151;8216 145;8217 146;8218 130;8220 147;8221 148;8222 132;8224 134;...
        8225 135;8226 149;8230 133;8240 137;8249 139;8250 155;8364 128;8482 153];
    
    isOctave=exist('OCTAVE_VERSION', 'builtin');
    if isOctave
        runtimename='Octave';
    else
        runtimename='Matlab';
        %convert to char here to prevent range errors in Octave
        origin=char(CPwin2UTF8(:,1));
        target=char(CPwin2UTF8(:,2));
    end
    %The regexp split option was introduced in R2007b.
    legacy.split = ifversion('<','R2007b','Octave','<',4);
    %Test if webread() is available
    legacy.UseURLread=isempty(which('webwrite'));
    %Change this line when Octave does support https
    legacy.allows_https=ifversion('>',0,'Octave','<',0);
end
if ... %enumerate all possible incorrect inputs
        nargin~=1 ...                                              %must have 1 input
        || ~( isa(filename,'char') || isa(filename,'string') ) ... %must be either char or string
        || ( isa(filename,'string') && numel(filename)~=1 ) ...    %if string, must be scalar
        || ( isa(filename,'char')   && numel(filename)==0 )        %if char, must be non-empty
    error('HJW:readfile:IncorrectInput',...
        'The file name must be a non-empty char or a scalar string.')
end
if isa(filename,'string'),filename=char(filename);end
if numel(filename)>=8 && ( strcmp(filename(1:7),'http://') || strcmp(filename(1:8),'https://') )
    isURL=true;
    if ~legacy.allows_https && strcmp(filename(1:8),'https://')
        warning('HJW:readfile:httpsNotSupported',...
            ['This implementation of urlread probably doesn''t allow https requests.',char(10),...
            'The next lines of code will probably result in an error.']) %#ok<CHARTEN>
    end
    str=readfile_URL_to_str(filename,legacy.UseURLread);
    if isa(str,'cell') %file was read from temporary downloaded version
        data=str;return
    end
else
    isURL=false;
end
if ~isOctave
    if ~isURL
        try
            str=fileread(filename);
        catch
            error('HJW:readfile:ReadFail',['%s could not read the file %s.\n',...
                'The file doesn''t exist or is not readable.'],...
                runtimename,filename)
        end
    end
    if ispc
        str_original=str;%make a backup
        %Convert from the Windows-1252 codepage (the default on a Windows machine) to UTF-8
        try
            [a,b]=ismember(str,origin);
            str(a)=target(b(a));
        catch
            %in case of an ismember memory error on ML6.5
            for n=1:numel(origin)
                str=strrep(str,origin(n),target(n));
            end
        end
        try
            if exist('native2unicode','builtin')
                %Probably introduced in R14 (v7.0)
                ThrowErrorIfNotUTF8file(str)
                str=native2unicode(uint8(str),'UTF8');
                str=char(str);
            else
                str=UTF8_to_str(str);
            end
        catch
            %ML6.5 doesn't support the "catch ME" syntax
            ME=lasterror;%#ok<LERR>
            if strcmp(ME.identifier,'HJW:UTF8_to_str:notUTF8')
                %Apparently it is not a UTF-8 file, as the converter failed, so undo the
                %Windows-1252 codepage re-mapping.
                str=str_original;
            else
                rethrow(ME)
            end
        end
    end
    if numel(str)>=1 && double(str(1))==65279
        %remove UTF BOM (U+FEFF) from text
        str(1)='';
    end
    str(str==13)='';
    if legacy.split
        s1=strfind(str,char(10));s2=s1;%#ok<CHARTEN>
        data=cell(numel(s1)+1,1);
        start_index=[s1 numel(str)+1];
        stop_index=[0 s2];
        for n=1:numel(start_index)
            data{n}=str((stop_index(n)+1):(start_index(n)-1));
        end
    else
        data=regexp(str,char(10),'split')'; %#ok<CHARTEN>
    end
else
    if ~isURL
        data = cell(0);
        fid = fopen (filename, 'r');
        if fid<0
            error('HJW:readfile:ReadFail',['%s could not read the file %s.\n',...
                'The file doesn''t exist or is not readable.'],...
                runtimename,filename)
        end
        i=0;
        while i==0 || ischar(data{i})
            i=i+1;
            data{i,1} = fgetl (fid);
        end
        fclose (fid);
        data = data(1:end-1);  % No EOL
    else
        %online file was already read to str, now convert str to cell array
        if legacy.split
            s1=strfind(str,char(10));s2=s1;%#ok<CHARTEN>
            data=cell(numel(s1)+1,1);
            start_index=[s1 numel(str)+1];
            stop_index=[0 s2];
            for n=1:numel(start_index)
                data{n,1}=str((stop_index(n)+1):(start_index(n)-1));
            end
        else
            data=regexp(str,char(10),'split')'; %#ok<CHARTEN>
        end
    end
    try
        data_original=data;
        for n=1:numel(data)
            %Use a global internally to keep track of chars>255 and reset that state for n==1.
            [data{n},pref]=UTF8_to_str(data{n},1,n==1);
        end
        if pref.state
            warning(pref.ME.identifier,pref.ME.message)
            %an error could be thrown like this:
            % error(pref.ME)
        end
    catch ME
        if strcmp(ME.identifier,'HJW:UTF8_to_str:notUTF8')
            %Apparently it is not a UTF-8 file, as the converter failed, so undo the Windows-1252
            %codepage re-mapping.
            data=data_original;
        else
            rethrow(ME)
        end
    end
end
end
function tf=ifversion(test,Rxxxxab,Oct_flag,Oct_test,Oct_ver)
%Determine if the current version satisfies a version restriction
%
% To keep the function fast, no input checking is done. This function returns a NaN if a release
% name is used that is not in the dictionary.
%
% Syntax:
% tf=ifversion(test,Rxxxxab)
% tf=ifversion(test,Rxxxxab,'Octave',test_for_Octave,v_Octave)
%
% Output:
% tf       - If the current version satisfies the test this returns true.
%            This works similar to verLessThan.
%
% Inputs:
% Rxxxxab - Char array containing a release description (e.g. 'R13', 'R14SP2' or 'R2019a') or the
%           numeric version.
% test    - Char array containing a logical test. The interpretation of this is equivalent to
%           eval([current test Rxxxxab]). For examples, see below.
%
% Examples:
% ifversion('>=','R2009a') returns true when run on R2009a or later
% ifversion('<','R2016a') returns true when run on R2015b or older
% ifversion('==','R2018a') returns true only when run on R2018a
% ifversion('==',9.8) returns true only when run on R2020a
% ifversion('<',0,'Octave','>',0) returns true only on Octave
%
% The conversion is based on a manual list and therefore needs to be updated manually, so it might
% not be complete. Although it should be possible to load the list from Wikipedia, this is not
% implemented.
%
%  _______________________________________________________________________
% | Compatibility | Windows 10  | Ubuntu 20.04 LTS | MacOS 10.15 Catalina |
% |---------------|-------------|------------------|----------------------|
% | ML R2020a     |  works      |  not tested      |  not tested          |
% | ML R2018a     |  works      |  works           |  not tested          |
% | ML R2015a     |  works      |  works           |  not tested          |
% | ML R2011a     |  works      |  works           |  not tested          |
% | ML 6.5 (R13)  |  works      |  not tested      |  not tested          |
% | Octave 5.2.0  |  works      |  works           |  not tested          |
% | Octave 4.4.1  |  works      |  not tested      |  works               |
% """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
%
% Version: 1.0.2
% Date:    2020-05-20
% Author:  H.J. Wisselink
% Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 )
% Email = 'h_j_wisselink*alumnus_utwente_nl';
% Real_email = regexprep(Email,{'*','_'},{'@','.'})

%The decimal of the version numbers are padded with a 0 to make sure v7.10 is larger than v7.9.
%This does mean that any numeric version input needs to be adapted. multiply by 100 and round to
%remove the potential for float rounding errors.
%Store in persistent for fast recall (don't use getpref, as that is slower than generating the
%variables and makes updating this function harder).
persistent  v_num v_dict octave
if isempty(v_num)
    %test if Octave is used instead of Matlab
    octave=exist('OCTAVE_VERSION', 'builtin');
    
    %get current version number
    v_num=version;
    ii=strfind(v_num,'.');
    if numel(ii)~=1,v_num(ii(2):end)='';ii=ii(1);end
    v_num=[str2double(v_num(1:(ii-1))) str2double(v_num((ii+1):end))];
    v_num=v_num(1)+v_num(2)/100;
    v_num=round(100*v_num);%remove float rounding errors
    
    %get dictionary to use for ismember
    v_dict={...
        'R13' 605;'R13SP1' 605;'R13SP2' 605;'R14' 700;'R14SP1' 700;'R14SP2' 700;'R14SP3' 701;...
        'R2006a' 702;'R2006b' 703;'R2007a' 704;'R2007b' 705;'R2008a' 706;'R2008b' 707;...
        'R2009a' 708;'R2009b' 709;'R2010a' 710;'R2010b' 711;'R2011a' 712;'R2011b' 713;...
        'R2012a' 714;'R2012b' 800;'R2013a' 801;'R2013b' 802;'R2014a' 803;'R2014b' 804;...
        'R2015a' 805;'R2015b' 806;'R2016a' 900;'R2016b' 901;'R2017a' 902;'R2017b' 903;...
        'R2018a' 904;'R2018b' 905;'R2019a' 906;'R2019b' 907;'R2020a' 908};
end

if octave
    if nargin==2
        warning('HJW:ifversion:NoOctaveTest',...
            ['No version test for Octave was provided.',char(10),...
            'This function might return an unexpected outcome.']) %#ok<CHARTEN>
        %Use the same test as for Matlab, which will probably fail.
        L=ismember(v_dict(:,1),Rxxxxab);
        if sum(L)~=1
            warning('HJW:ifversion:NotInDict',...
                'The requested version is not in the hard-coded list.')
            tf=NaN;return
        else
            v=v_dict{L,2};
        end
    elseif nargin==4
        %undocumented shorthand syntax: skip the 'Octave' argument
        [test,v]=deal(Oct_flag,Oct_test);
        %convert 4.1 to 401
        v=0.1*v+0.9*fix(v);v=round(100*v);
    else
        [test,v]=deal(Oct_test,Oct_ver);
        %convert 4.1 to 401
        v=0.1*v+0.9*fix(v);v=round(100*v);
    end
else
    %convert R notation to numeric and convert 9.1 to 901
    if isnumeric(Rxxxxab)
        v=0.1*Rxxxxab+0.9*fix(Rxxxxab);v=round(100*v);
    else
        L=ismember(v_dict(:,1),Rxxxxab);
        if sum(L)~=1
            warning('HJW:ifversion:NotInDict',...
                'The requested version is not in the hard-coded list.')
            tf=NaN;return
        else
            v=v_dict{L,2};
        end
    end
end
switch test
    case '=='
        tf= v_num == v;
    case '<'
        tf= v_num <  v;
    case '<='
        tf= v_num <= v;
    case '>'
        tf= v_num >  v;
    case '>='
        tf= v_num >= v;
end
end
function str=readfile_URL_to_str(url,UseURLread)
%Read the contents of a file to a char array.
%
%Attempt to download to the temp folder, read the file, then delete it.
%If that fails, read to a char array with urlread/webread.
try
    %Generate a random file name in the temp folder
    fn=tmpname('readfile_from_URL_tmp_','.txt');
    try
        RevertToUrlread=false;%in case the saving+reading fails
        
        %Try to download
        if UseURLread,fn=urlwrite(url,fn);else,fn=websave(fn,url);end %#ok<URLWR>
        
        %Try to read
        str=readfile(fn);
    catch
        RevertToUrlread=true;
    end
    
    %Delete the temp file
    try if exist(fn,'file'),delete(fn);end,catch,end
    
    if RevertToUrlread,error('revert to urlread'),end
catch
    %Read to a char array and let these functions throw an error in case of HTML errors and/or
    %missing connectivity.
    if UseURLread,str=urlread(url);else,str=webread(url);end %#ok<URLRD>
end
end
function ThrowErrorIfNotUTF8file(str)
%Test if the char input is likely to be UTF8
%
%This uses the same tests as the UTF8_to_str function.
%Octave has poor support for chars >255, but that is ignored in this function.

if any(str>255)
    error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
end
str=char(str);

%Matlab doesn't support 4-byte chars in the same way as 1-3 byte chars. So we ignore them and start
%with the 3-byte chars (starting with 1110xxxx).
val_byte3=bin2dec('11100000');
byte3=str>=val_byte3;
if any(byte3)
    byte3=find(byte3)';
    try
        byte3=str([byte3 (byte3+1) (byte3+2)]);
    catch
        if numel(str)<(max(byte3)+2)
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        else
            rethrow(lasterror) %#ok<LERR> no "catch ME" syntax in ML6.5
        end
    end
    byte3=unique(byte3,'rows');
    S2=mat2cell(char(byte3),ones(size(byte3,1),1),3);
    for n=1:numel(S2)
        bin=dec2bin(double(S2{n}))';
        %To view the binary data, you can use this: bin=bin(:)';
        %Remove binary header:
        %1110xxxx10xxxxxx10xxxxxx
        %    xxxx  xxxxxx  xxxxxx
        if ~strcmp('11101010',bin([1 2 3 4 8+1 8+2 16+1 16+2]))
            %Check if the byte headers match the UTF8 standard
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        end
    end
end
%Next, the 2-byte chars (starting with 110xxxxx)
val_byte2=bin2dec('11000000');
byte2=str>=val_byte2 & str<val_byte3;%Exclude the already checked chars
if any(byte2)
    byte2=find(byte2)';
    try
        byte2=str([byte2 (byte2+1)]);
    catch
        if numel(str)<(max(byte2)+1)
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        else
            rethrow(lasterror) %#ok<LERR> no "catch ME" syntax in ML6.5
        end
    end
    byte2=unique(byte2,'rows');
    S2=mat2cell(byte2,ones(size(byte2,1),1),2);
    for n=1:numel(S2)
        bin=dec2bin(double(S2{n}))';
        %To view the binary data, you can use this: bin=bin(:)';
        %Remove binary header:
        %110xxxxx10xxxxxx
        %   xxxxx  xxxxxx
        if ~strcmp('11010',bin([1 2 3 8+1 8+2]))
            %Check if the byte headers match the UTF8 standard
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        end
    end
end
end
function str=tmpname(StartFilenameWith,ext)
%Inject a string in the file name part returned by the tempname function.
if nargin<1,StartFilenameWith='';end
if ~isempty(StartFilenameWith),StartFilenameWith=[StartFilenameWith '_'];end
if nargin<2,ext='';else,if ~strcmp(ext(1),'.'),ext=['.' ext];end,end
str=tempname;
[p,f]=fileparts(str);
str=fullfile(p,[StartFilenameWith f ext]);
end
function [unicode,flag]=UTF8_to_str(UTF8,behavior__char_geq256,ResetOutputFlag)
%Convert UTF8 to actual char values
%
%This function replaces the syntax str=native2unicode(uint8(UTF8),'UTF8');
%This function throws an error if the input is not possibly UTF8.
%
%To deal with the limited char support in Octave, you can set a preference for what should happen,
%(use the UTF8_to_str___behavior__char_geq256 preference in the HJW group). You can set it to 5
%levels:
%0 (ignore), 1 (reported in global), 2 (reported in setpref), 3 (throw warning), 4 (throw error)
%
%With the level set to 1, you can use the global variable HJW___UTF8_to_str___error_was_triggered
%to see if there is a char>255. If that was the case, the state field will be set to true. This
%variable also contains an ME struct.
%With the level set to 2 you can retrieve a similar variable with
%getpref('HJW','UTF8_to_str___error_was_triggered'). These will not overwrite each other.
%
%This struct is also returned as the second output variable.

% %test case:
% c=[char(hex2dec('0024')) char(hex2dec('00A2')) char(hex2dec('20AC'))];
% c=[c c+1 c];
% UTF8=unicode2native(c,'UTF8');
% native=UTF8_to_str(UTF8);
% disp(c)
% disp(native)

%Set the default behavior for chars>255 (only relevant on Octave)
default_behavior__char_geq256=1;
%    0: ignore
%    1: report in global
%    2: report in pref
%    3: throw warning
%    4: throw error

if any(UTF8>255)
    error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
end
UTF8=char(UTF8);

persistent isOctave pref
global HJW___UTF8_to_str___error_was_triggered%globals generally are a bad idea, so use a long name
if isempty(isOctave)
    %initialize persistent variable (pref will be initialized later)
    isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;
end
if isOctave
    if nargin<2
        behavior__char_geq256=getpref('HJW',...%toolbox name or author initials as group ID
            ['UTF8_to_str___',...%function group
            'behavior__char_geq256'],...%preference name
            default_behavior__char_geq256);
    end
    if nargin<3
        ResetOutputFlag=true;
    end
    if behavior__char_geq256==1
        %Overwrite persistent variable with the contents of the global. This ensures changes made
        %to this variable outside this function are not overwritten.
        pref=HJW___UTF8_to_str___error_was_triggered;
    end
    
    ID='HJW:UTF8_to_str:charnosupport';
    msg='Chars greater than 255 are not supported on Octave.';
    if ResetOutputFlag || isempty(pref)
        pref=struct(...
            'state',false,...
            'ME',struct('message',msg,'identifier',ID),...
            'default',default_behavior__char_geq256);
        if behavior__char_geq256==1
            HJW___UTF8_to_str___error_was_triggered=pref;
        elseif behavior__char_geq256==2
            %Don't bother overwriting this if it is not going to be used. Calling prefs takes a
            %relatively long time, so it should be avoided when not necessary.
            setpref('HJW',...%toolbox name or author initials as group ID
                ['UTF8_to_str___',...%function group
                'error_was_triggered'],...%preference name
                pref);
        end
    end
end

%Matlab doesn't support 4-byte chars in the same way as 1-3 byte chars. So we ignore them and start
%with the 3-byte chars (starting with 1110xxxx). The reason for this difference is that a 3-byte
%char will fit in a uint16, which is how Matlab stores chars internally.
val=bin2dec('11100000');
byte3=UTF8>=val;
if any(byte3)
    byte3=find(byte3)';
    try
        byte3=UTF8([byte3 (byte3+1) (byte3+2)]);
    catch
        if numel(UTF8)<(max(byte3)+2)
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        else
            rethrow(lasterror) %#ok<LERR> no "catch ME" syntax in ML6.5
        end
    end
    byte3=unique(byte3,'rows');
    S2=mat2cell(char(byte3),ones(size(byte3,1),1),3);
    for n=1:numel(S2)
        bin=dec2bin(double(S2{n}))';
        %To view the binary data, you can use this: bin=bin(:)';
        %Remove binary header:
        %1110xxxx10xxxxxx10xxxxxx
        %    xxxx  xxxxxx  xxxxxx
        if ~strcmp('11101010',bin([1 2 3 4 8+1 8+2 16+1 16+2]))
            %Check if the byte headers match the UTF8 standard
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        end
        bin([1 2 3 4 8+1 8+2 16+1 16+2])='';
        if ~isOctave
            S3=char(bin2dec(bin));
        else
            val=bin2dec(bin');%Octave needs an extra transpose
            if behavior__char_geq256>0 && val>255
                %See explanation above for the reason behind this code.
                pref.state=true;
                if behavior__char_geq256==1
                    HJW___UTF8_to_str___error_was_triggered.state=true;
                elseif behavior__char_geq256==2 && ~(pref.state) %(no need to set if already true)
                    setpref('HJW',...%toolbox name or author initials as group ID
                        ['UTF8_to_str___',...%function group
                        'error_was_triggered'],...%preference name
                        pref)
                elseif behavior__char_geq256==3
                    warning(ID,msg)
                else
                    error(ID,msg)
                end
            end
            %Prevent range error warnings. Any invalid char value has already been handled above.
            w=warning('off','all');
            S3=char(val);
            warning(w)
        end
        %Perform replacement
        UTF8=strrep(UTF8,S2{n},S3);
    end
end
%Next, the 2-byte chars (starting with 110xxxxx)
val=bin2dec('11000000');
byte2=UTF8>=val & UTF8<256;%Exclude the already converted chars
if any(byte2)
    byte2=find(byte2)';
    try
        byte2=UTF8([byte2 (byte2+1)]);
    catch
        if numel(UTF8)<(max(byte2)+1)
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        else
            rethrow(lasterror) %#ok<LERR> no "catch ME" syntax in ML6.5
        end
    end
    byte2=unique(byte2,'rows');
    S2=mat2cell(byte2,ones(size(byte2,1),1),2);
    for n=1:numel(S2)
        bin=dec2bin(double(S2{n}))';
        %To view the binary data, you can use this: bin=bin(:)';
        %Remove binary header:
        %110xxxxx10xxxxxx
        %   xxxxx  xxxxxx
        if ~strcmp('11010',bin([1 2 3 8+1 8+2]))
            %Check if the byte headers match the UTF8 standard
            error('HJW:UTF8_to_str:notUTF8','Input is not UTF8')
        end
        bin([1 2 3 8+1 8+2])='';
        if ~isOctave
            S3=char(bin2dec(bin));
        else
            val=bin2dec(bin');%Octave needs an extra transpose
            if behavior__char_geq256>0 && val>255
                pref.state=true;
                if behavior__char_geq256==1
                    HJW___UTF8_to_str___error_was_triggered.state=true;
                elseif behavior__char_geq256==2 && ~(pref.state) %(no need to set if already true)
                    setpref('HJW',...%toolbox name or author initials as group ID
                        ['UTF8_to_str___',...%function group
                        'error_was_triggered'],...%preference name
                        pref)
                elseif behavior__char_geq256==3
                    warning(ID,msg)
                else
                    error(ID,msg)
                end
            end
            %Prevent range error warnings. Any invalid char value has already been handled above.
            w=warning('off','all');
            S3=char(val);
            warning(w)
        end
        %Perform replacement
        UTF8=strrep(UTF8,S2{n},S3);
    end
end
unicode=UTF8;
flag=pref;
end