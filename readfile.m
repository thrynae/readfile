function data=readfile(filename,varargin)
%Read a UTF-8 or ANSI (US-ASCII) file
%
% Syntax:
%    data=readfile(filename)
%    data=readfile(___,options)
%    data=readfile(___,Name,Value)
%    filename: char array with either relative or absolute path, or a URL
%    data: n-by-1 cell (1 cell per line in the file, even empty lines)
%    options: struct with Name,Value parameters. Missing parameter are filled with the default.
%
% Name,Value parameters:
%    print_to_con : A logical that controls whether warnings and other output will be printed to
%                   the command window. Errors can't be turned off. [default=true;] if either
%                   print_to_fid or print_to_obj is specified then [default=false]
%    print_to_fid : The file identifier where console output will be printed. Errors and warnings
%                   will be printed including the call stack. You can provide the fid for the
%                   command window (fid=1) to print warnings as text. Errors will be printed to the
%                   specified file before being actually thrown. [default=[];]
%                   If both print_to_fid and print_to_obj are empty, this will have the effect of
%                   suppressing every output except errors.
%                   This parameter does not affect warnings or errors during input parsing.
%    print_to_obj : The handle to an object with a String property, e.g. an edit field in a GUI
%                   where console output will be printed. Messages with newline characters
%                   (ignoring trailing newlines) will be returned as a cell array. This includes
%                   warnings and errors, which will be printed without the call stack. Errors will
%                   be written to the object before the error is actually thrown. [default=[];]
%                   If both print_to_fid and print_to_obj are empty, this will have the effect of
%                   suppressing every output except errors.
%                   This parameter does not affect warnings or errors during input parsing.
%    err_on_ANSI :  If set to true, an error will be thrown when the input file is not recognized
%                   as UTF-8 encoded. This should normally not be an issue, as ANSI files can be
%                   read as well with this function. [default=false;]
%
% This function is aimed at providing a reliable method of reading a file. The backbone of this
% function is fread, supplemented by the fileread function. These work in slightly different ways
% and can be used under different circumstances. An attempt is made to detect the encoding (UTF-8
% or ANSI), apply the transcoding and returning the file as an n-by-1 cell array for files with
% n lines.
% You can redirect all outputs (errors only partially) to a file or a graphics object, so you can
% more easily use this function in a GUI or allow it to write to a log file.
%
% The test for being UTF-8 can fail. For files with chars in the 128:255 range, the test will often
% determine the encoding correctly, but it might fail, especially for files with encoding errors.
% Online files are much more limited than offline files. To avoid this the files are downloaded to
% tempdir() and deleted after reading. To avoid this the files are
% downloaded to tempdir() and deleted after reading. An additional fallback reads online files with
% webread/urlread, although this will often result in an incorrect output. This should only be
% relevant if there is no write access to the tempdir().
%
% Octave encodes characters as UTF-8 in chars (although it allows char values 128-255 'by
% accident'), while Matlab uses UTF-16 to encode characters. This means the sizes of the char
% arrays might not be consistent between Matlab and Octave. It is important to remember that a
% scalar char is not guaranteed to be a single Unicode character, and that a single Unicode
% character is not guaranteed to be a single glyph. This is especially important when relying on
% exact positions and when sharing data/code between Matlab and Octave.
%
%  _______________________________________________________________________
% | Compatibility | Windows 10  | Ubuntu 20.04 LTS | MacOS 10.15 Catalina |
% |---------------|-------------|------------------|----------------------|
% | ML R2020b     |  works      |  not tested      |  not tested          |
% | ML R2018a     |  works      |  works           |  not tested          |
% | ML R2015a     |  works      |  works           |  not tested          |
% | ML R2011a     |  works      |  works           |  not tested          |
% | ML 6.5 (R13)  |  works      |  not tested      |  not tested          |
% | Octave 5.2.0  |  works      |  works           |  not tested          |
% | Octave 4.4.1  |  works      |  not tested      |  works               |
% """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
%
% Version: 3.0.0
% Date:    2020-11-07
% Author:  H.J. Wisselink
% Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 )
% Email = 'h_j_wisselink*alumnus_utwente_nl';
% Real_email = regexprep(Email,{'*','_'},{'@','.'})

% Tested with 4 files with the following chars:
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
% list_of_chars4=[...
%    008986,009785,010084,128025,128512,128512,128513,128522,128550,128551,128552,128553,128555,...
%    128561,128578,128583,129343];
if nargin<1
    error('HJW:readfile:nargin','Incorrect number of input argument.')
end
if ~(nargout==0 || nargout==1) %might trigger 'MATLAB:TooManyOutputs' instead
    error('HJW:WBM:nargout','Incorrect number of output argument.')
end
[success,opts,ME]=readfile_parse_inputs(filename,varargin{:});
if ~success
    %The throwAsCaller function was introduced in R2007b, hence the rethrow here.
    rethrow(ME)
else
    [legacy,UseURLread,err_on_ANSI]=deal(opts.legacy,opts.UseURLread,opts.err_on_ANSI);
    print_2=struct('con',opts.print_2_con,'fid',opts.print_2_fid,'obj',opts.print_2_obj);
end

if isa(filename,'string'),filename=char(filename);end
if numel(filename)>=8 && ( strcmp(filename(1:7),'http://') || strcmp(filename(1:8),'https://') )
    if ~legacy.allows_https && strcmp(filename(1:8),'https://')
        warning_(print_2,'HJW:readfile:httpsNotSupported',...
            ['This implementation of urlread probably doesn''t allow https requests.',char(10),...
            'The next lines of code will probably result in an error.']) %#ok<CHARTEN>
    end
    str=readfile_from_URL(filename,UseURLread,print_2);
    if isa(str,'cell') %file was read from temporary downloaded version
        data=str;
    else
        %This means the download failed. Some files will not work.
        invert=true;
        str=convert_from_codepage(str,invert);
        try
            [ii,isUTF8,converted]=UTF8_to_unicode(str); %#ok<ASGLU>
        catch
            ME=lasterror; %#ok<LERR>
            if strcmp(ME.identifier,'HJW:UTF8_to_unicode:notUTF8')
                isUTF8=false;
            else
                error_(print_2,ME)
            end
        end
        if isUTF8
            str=unicode_to_char(converted);
        end
        data=char2cellstr(str);
    end
else
    data=readfile_from_file(filename,print_2,err_on_ANSI);
end
end
function out=bsxfun_plus(in1,in2)
%implicit expansion for plus(), but without any input validation
try
    out=in1+in2;
catch
    try
        out=bsxfun(@plus,in1,in2);
    catch
        sz1=size(in1);                    sz2=size(in2);
        in1=repmat(in1,max(1,sz2./sz1));  in2=repmat(in2,max(1,sz1./sz2));
        out=in1+in2;
    end
end
end
function c=char2cellstr(str)
%Split char vector to cell (1 cell element per line)
newlineidx=[0 find(str==10) numel(str)+1];
c=cell(numel(newlineidx)-1,1);
for n=1:numel(c)
    s1=(newlineidx(n  )+1);
    s2=(newlineidx(n+1)-1);
    c{n}=str(s1:s2);
end
end
function str=convert_from_codepage(str,inverted)
%Convert from the Windows-1252 codepage
persistent or ta
if isempty(or)
    %This list is complete for all characters (up to 0xFFFF) that can be encoded with ANSI.
    CPwin2UTF8=[338 140;339 156;352 138;353 154;376 159;381 142;382 158;402 131;710 136;732 152;
        8211 150;8212 151;8216 145;8217 146;8218 130;8220 147;8221 148;8222 132;8224 134;8225 135;
        8226 149;8230 133;8240 137;8249 139;8250 155;8364 128;8482 153];
    or=CPwin2UTF8(:,2);ta=CPwin2UTF8(:,1);
end
if nargin>1 && inverted
    origin=ta;target=or;
else
    origin=or;target=ta;
end
str=uint32(str);
for m=1:numel(origin)
    str=PatternReplace(str,origin(m),target(m));
end
end
function error_(options,varargin)
%Print an error to the command window, a file and/or the String property of an object.
%The error will first be written to the file and object before being actually thrown.
%
%The intention is to allow replacement of every error(___) call with error_(options,___).
%
% NB: the error trace that is written to a file or object may differ from the trace displayed by
% calling the builtin error function. This was only observed when evaluating code sections. 
%
%options.fid.boolean: if true print error to file (options.fid.fid)
%options.obj.boolean: if true print error to object (options.obj.obj)
%
%syntax:
%  error_(options,msg)
%  error_(options,msg,A1,...,An)
%  error_(options,id,msg)
%  error_(options,id,msg,A1,...,An)
%  error_(options,ME)               %equivalent to rethrow(ME)

%parse input to find id, msg, stack and the trace str
if isempty(options),options=struct;end%allow empty input to revert to default
if ~isfield(options,'fid'),options.fid.boolean=false;end
if ~isfield(options,'obj'),options.obj.boolean=false;end
if nargin==2
    %  error_(options,msg)
    %  error_(options,ME)
    if isa(varargin{1},'struct') || isa(varargin{1},'MException')
        ME=varargin{1};
        try
            stack=ME.stack;%use original call stack if possible
            trace=get_trace(0,stack);
        catch
            [trace,stack]=get_trace(2);
        end
        id=ME.identifier;
        msg=ME.message;
        pat='Error using <a href="matlab:matlab.internal.language.introspective.errorDocCallback(';
        %This pattern may occur when using try error(id,msg),catch,ME=lasterror;end instead of
        %catching the MException with try error(id,msg),catch ME,end.
        %This behavior is not stable enough to robustly check for it, but it only occurs with
        %lasterror, so we can use that.
        if isa(ME,'struct') && numel(msg)>numel(pat) && strcmp(pat,msg(1:numel(pat)))
            %Strip the first line (which states 'error in function (line)', instead of only msg).
            msg(1:find(msg==10,1))='';
        end
    else
        [trace,stack]=get_trace(2);
        [id,msg]=deal('',varargin{1});
    end
else
    [trace,stack]=get_trace(2);
    if ~isempty(strfind(varargin{1},'%')) % id can't contain a percent symbol
        %  error_(options,msg,A1,...,An)
        id='';
        A1_An=varargin(2:end);
        msg=sprintf(varargin{1},A1_An{:});
    else
        %  error_(options,id,msg)
        %  error_(options,id,msg,A1,...,An)
        id=varargin{1};
        msg=varargin{2};
        if nargin>3
            A1_An=varargin(3:end);
            msg=sprintf(msg,A1_An{:});
        end
    end
end
ME=struct('identifier',id,'message',msg,'stack',stack);

%print to object
if options.obj.boolean
    msg_=msg;while msg_(end)==10,msg_(end)='';end%crop trailing newline
    if any(msg_==10)  % parse to cellstr and prepend error
        msg_=regexp_outkeys(['Error: ' msg_],char(10),'split'); %#ok<CHARTEN>
    else              % only prepend error
        msg_=['Error: ' msg_];
    end
    set(options.obj.obj,'String',msg_)
end

%print to file
if options.fid.boolean
    fprintf(options.fid.fid,'Error: %s\n%s',msg,trace);
end

%Actually throw the error.
rethrow(ME)
end
function [str,stack]=get_trace(skip_layers,stack)
if nargin==0,skip_layers=1;end
if nargin<2, stack=dbstack;end
stack(1:skip_layers)=[];

%parse ML6.5 style of dbstack (name field includes full file location)
if ~isfield(stack,'file')
    for n=1:numel(stack)
        tmp=stack(n).name;
        if strcmp(tmp(end),')')
            %internal function
            ind=strfind(tmp,'(');
            name=tmp( (ind(end)+1):(end-1) );
            file=tmp(1:(ind(end)-2));
        else
            file=tmp;
            [ignore,name]=fileparts(tmp); %#ok<ASGLU>
        end
        [ignore,stack(n).file]=fileparts(file); %#ok<ASGLU>
        stack(n).name=name;
    end
end

%parse Octave style of dbstack (file field includes full file location)
persistent IsOctave,if isempty(IsOctave),IsOctave=exist('OCTAVE_VERSION', 'builtin');end
if IsOctave
    for n=1:numel(stack)
        [ignore,stack(n).file]=fileparts(stack(n).file); %#ok<ASGLU>
    end
end

%create actual char array with a (potentially) modified stack
s=stack;
c1='>';
str=cell(1,numel(s)-1);
for n=1:numel(s)
    [ignore_path,s(n).file,ignore_ext]=fileparts(s(n).file); %#ok<ASGLU>
    if n==numel(s),s(n).file='';end
    if strcmp(s(n).file,s(n).name),s(n).file='';end
    if ~isempty(s(n).file),s(n).file=[s(n).file '>'];end
    str{n}=sprintf('%c In %s%s (line %d)\n',c1,s(n).file,s(n).name,s(n).line);
    c1=' ';
end
str=horzcat(str{:});
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
% ifversion('==',9.9) returns true only when run on R2020b
% ifversion('<',0,'Octave','>',0) returns true only on Octave
%
% The conversion is based on a manual list and therefore needs to be updated manually, so it might
% not be complete. Although it should be possible to load the list from Wikipedia, this is not
% implemented.
%
%  _______________________________________________________________________
% | Compatibility | Windows 10  | Ubuntu 20.04 LTS | MacOS 10.15 Catalina |
% |---------------|-------------|------------------|----------------------|
% | ML R2020b     |  works      |  not tested      |  not tested          |
% | ML R2018a     |  works      |  works           |  not tested          |
% | ML R2015a     |  works      |  works           |  not tested          |
% | ML R2011a     |  works      |  works           |  not tested          |
% | ML 6.5 (R13)  |  works      |  not tested      |  not tested          |
% | Octave 5.2.0  |  works      |  works           |  not tested          |
% | Octave 4.4.1  |  works      |  not tested      |  works               |
% """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
%
% Version: 1.0.4
% Date:    2020-09-28
% Author:  H.J. Wisselink
% Licence: CC by-nc-sa 4.0 ( https://creativecommons.org/licenses/by-nc-sa/4.0 )
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
    ii=strfind(v_num,'.');if numel(ii)~=1,v_num(ii(2):end)='';ii=ii(1);end
    v_num=[str2double(v_num(1:(ii-1))) str2double(v_num((ii+1):end))];
    v_num=v_num(1)+v_num(2)/100;v_num=round(100*v_num);
    
    %get dictionary to use for ismember
    v_dict={...
        'R13' 605;'R13SP1' 605;'R13SP2' 605;'R14' 700;'R14SP1' 700;'R14SP2' 700;'R14SP3' 701;
        'R2006a' 702;'R2006b' 703;'R2007a' 704;'R2007b' 705;'R2008a' 706;'R2008b' 707;
        'R2009a' 708;'R2009b' 709;'R2010a' 710;'R2010b' 711;'R2011a' 712;'R2011b' 713;
        'R2012a' 714;'R2012b' 800;'R2013a' 801;'R2013b' 802;'R2014a' 803;'R2014b' 804;
        'R2015a' 805;'R2015b' 806;'R2016a' 900;'R2016b' 901;'R2017a' 902;'R2017b' 903;
        'R2018a' 904;'R2018b' 905;'R2019a' 906;'R2019b' 907;'R2020a' 908;'R2020b',909};
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
    case '==', tf= v_num == v;
    case '<' , tf= v_num <  v;
    case '<=', tf= v_num <= v;
    case '>' , tf= v_num >  v;
    case '>=', tf= v_num >= v;
end
end
function out=PatternReplace(in,pattern,rep)
%Functionally equivalent to strrep, but extended to more data types.
out=in(:)';
if numel(pattern)==0
    L=false(size(in));
elseif numel(rep)>numel(pattern)
    error('not implemented (padding required)')
else
    L=true(size(in));
    for n=1:numel(pattern)
        k=find(in==pattern(n));
        k=k-n+1;k(k<1)=[];
        %k contains the indices of the beginning of each match
        L2=false(size(L));L2(k)=true;
        L= L & L2;
        if ~any(L),break,end
    end
end
k=find(L);
if ~isempty(k)
    for n=1:numel(rep)
        out(k+n-1)=rep(n);
    end
    if numel(rep)==0,n=0;end
    if numel(pattern)>n
        k=k(:);%enforce direction
        remove=(n+1):numel(pattern);
        idx=bsxfun_plus(k,remove-1);
        out(idx(:))=[];
    end
end
end
function str=readfile_from_file(filename,print_2,err_on_ANSI)
if nargin==1,print_2=struct;err_on_ANSI=false;end
persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
persistent ME_file_access
if isempty(ME_file_access)
    if isOctave,runtime='Octave';else,runtime='Matlab';end
    ME_file_access=struct('identifier','HJW:readfile:ReadFail','message',...
        sprintf('%s could not read the file %s.\nThe file doesn''t exist or is not readable.',...
        runtime,filename));
end

fid=fopen(filename,'rb');
if fid<0,error_(print_2,ME_file_access),end
data=fread(fid,'uint8');
fclose(fid);
data=data.';
try
    isUTF8=true;
    converted=UTF8_to_unicode(data);
catch
    ME=lasterror; %#ok<LERR>
    if strcmp(ME.identifier,'HJW:UTF8_to_unicode:notUTF8')
        isUTF8=false;
        if err_on_ANSI
            error_(print_2,'HJW:readfile:notUTF8',...
                'The provided file "%s" is not a correctly encoded UTF-8 file.',filename)
        end
    else
        error_(print_2,ME)
    end
end

if isOctave
    if isUTF8
        str=converted;
    else
        try str=fileread(filename);catch,error_(print_2,ME_file_access),end
        str=convert_from_codepage(str);
    end
else
    if ispc
        if isUTF8
            str=converted;
        else
            if ifversion('<',7)
                try str=fileread(filename);catch,error_(print_2,ME_file_access),end
                str=convert_from_codepage(str);
            else
                try str=fileread(filename);catch,error_(print_2,ME_file_access),end
            end
        end
    else %assuming mac will work the same as Ubuntu
        if isUTF8
            str=converted;
        else
            str=convert_from_codepage(data);
        end
    end
end

%Remove carriage returns and UTF BOM (U+FEFF) from text.
str(str==13)=[];if numel(str)>=1 && double(str(1))==65279,str(1)=[];end
str=unicode_to_char(str);
str=char2cellstr(str);
end
function str=readfile_from_URL(url,UseURLread,print_to)
%Read the contents of a file to a char array.
%
%Attempt to download to the temp folder, read the file, then delete it.
%If that fails, read to a char array with urlread/webread.
try
    RevertToUrlread=false;%in case the saving+reading fails
    %Generate a random file name in the temp folder
    fn=tmpname('readfile_from_URL_tmp_','.txt');
    try
        %Try to download
        if UseURLread,fn=urlwrite(url,fn);else,fn=websave(fn,url);end %#ok<URLWR>
        
        %Try to read
        str=readfile_from_file(fn);
    catch
        RevertToUrlread=true;
    end
    
    %Delete the temp file
    try if exist(fn,'file'),delete(fn);end,catch,end
    
    if RevertToUrlread,error('revert to urlread'),end
catch
    %Read to a char array and let these functions throw an error in case of HTML errors and/or
    %missing connectivity.
    try
        if UseURLread,str=urlread(url);else,str=webread(url);end %#ok<URLRD>
    catch
        error_(print_to,lasterror) %#ok<LERR>
    end
end
end
function [success,options,ME]=readfile_parse_inputs(filename,varargin)
%Parse the inputs of the readfile function
% It returns a success flag, the parsed options, and an ME struct.
% As input, the options should either be entered as a struct or as Name,Value pairs. Missing fields
% are filled from the default.

%pre-assign outputs
success=false;
options=struct;
ME=struct('identifier','','message','');

%test the required input

if ... %enumerate all possible incorrect inputs
        ~( isa(filename,'char') || isa(filename,'string') ) || ... %must be either char or string
        ( isa(filename,'string') && numel(filename)~=1 )    || ... %if string, must be scalar
        ( isa(filename,'char')   && numel(filename)==0 )           %if char, must be non-empty
    ME.identifier='HJW:readfile:IncorrectInput';
    ME.message='The file name must be a non-empty char or a scalar string.';
    return
end

persistent default
if isempty(default)
    %The regexp split option was introduced in R2007b.
    legacy.split = ifversion('<','R2007b','Octave','<',4);
    %Change this line when Octave does support https.
    legacy.allows_https=ifversion('>',0,'Octave','<',0);
    default.legacy=legacy;
    %Test if webread() and websave() are both available.
    default.UseURLread=isempty(which('webread')) || isempty(which('websave'));
    
    default.print_2_con=true;%default changes if the two other fields are specified
    default.print_2_fid.boolean=false;
    default.print_2_obj.boolean=false;
    
    default.err_on_ANSI=false;
end
%The required inputs are checked, so now we need to return the default options if there are no
%further inputs.
if nargin==1
    options=default;
    success=true;
    return
end

%Test the optional inputs.
struct_input=nargin==2 && isa(varargin{1},'struct');
NameValue_input=mod(nargin,2)==1 && ...
    all(cellfun('isclass',varargin(1:2:end),'char'));
if ~( struct_input || NameValue_input )
    ME.message=['The second input (options) is expected to be either a struct, ',...
        'or consist of Name,Value pairs.'];
    ME.identifier='HJW:readfile:incorrect_input_options';
    return
end
if NameValue_input
    %Convert the Name,Value to a struct.
    for n=1:2:numel(varargin)
        try
            options.(varargin{n})=varargin{n+1};
        catch
            ME.message='Parsing of Name,Value pairs failed.';
            ME.identifier='HJW:readfile:incorrect_input_NameValue';
            return
        end
    end
else
    options=varargin{1};
end
fn=fieldnames(options);
for k=1:numel(fn)
    curr_option=fn{k};
    item=options.(curr_option);
    ME.identifier=['HJW:readfile:incorrect_input_opt_' lower(curr_option)];
    switch curr_option
        case 'UseURLread'
            [passed,item]=test_if_scalar_logical(item);
            if ~passed
                ME.message='UseURLread should be either true or false';
                return
            end
            %Force the use of urlread/urlwrite if websave/webread are not available.
            options.UseURLread=item || default.UseURLread;
        case 'err_on_ANSI'
            [passed,item]=test_if_scalar_logical(item);
            if ~passed
                ME.message='err_on_ANSI should be either true or false';
                return
            end
            options.show_UTF_err=item;
        case 'print_to_fid'
            if isempty(item)
                options.print_2_fid.boolean=false;
            else
                options.print_2_fid.boolean=true;
                try position=ftell(item);catch,position=-1;end
                if item~=1 && position==-1
                    ME.message=['Invalid print_to_fid parameter: ',...
                        'should be a valid file identifier or 1'];
                    return
                end
                options.print_2_fid.fid=item;
            end
        case 'print_to_obj'
            if isempty(item)
                options.print_2_obj.boolean=false;
            else
                options.print_2_obj.boolean=true;
                try
                    txt=get(item,'String'); %see if this triggers an error
                    set(item,'String','');  %test if property is writeable
                    set(item,'String',txt); %restore
                    options.print_2_obj.obj=item;
                catch
                    ME.message=['Invalid print_to_obj parameter: ',...
                        'should be a handle to an object with a writeable String property'];
                    return
                end
            end
        case 'print_to_con'
            [passed,options.print_2_con]=test_if_scalar_logical(item);
            if ~passed
                ME.message='print_to_con should be either true or false';
                return
            end
    end
end
if ~isfield(options,'print_2_con') && ...
        ( isfield(options,'print_2_fid') || isfield(options,'print_2_obj') )
    %If either fid or obj is specified, the default for print_2_con is false.
    options.print_2_con=false;
end
%fill any missing fields
fn=fieldnames(default);
for k=1:numel(fn)
    if ~isfield(options,fn(k))
        options.(fn{k})=default.(fn{k});
    end
end
success=true;ME=[];
end
function [isLogical,val]=test_if_scalar_logical(val)
%Test if the input is a scalar logical or convertible to it.
%(use the first output to trigger an input error, use the second as the parsed input)
%
% Allowed values:
%- true or false
%- 1 or 0
%- 'on' or 'off'
%- matlab.lang.OnOffSwitchState.on or matlab.lang.OnOffSwitchState.off
persistent states
if isempty(states)
    states={true,false;...
        1,0;...
        'on','off'};
    try
        states(end+1,:)=eval('{"on","off"}');
    catch
    end
end
isLogical=true;
try
    for n=1:size(states,1)
        for m=1:2
            if isequal(val,states{n,m})
                val=states{1,m};return
            end
        end
    end
    if isa(val,'matlab.lang.OnOffSwitchState')
        val=logical(val);return
    end
catch
end
isLogical=false;
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
function str=unicode_to_char(unicode)
%Encode Unicode code points with UTF-16 on Matlab and UTF-8 on Octave.
%Input is implicitly converted to a row-vector.

[char_list,ignore,positions]=unique(unicode); %#ok<ASGLU>
str=cell(1,numel(unicode));
persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
if ~isOctave
    %encode as UTF-16
    for n=1:numel(char_list)
        str_element=unicode_to_UTF16(char_list(n));
        str_element=uint16(str_element);
        str(positions==n)={str_element};
    end
else
    %encode as UTF-8
    for n=1:numel(char_list)
        str_element=unicode_to_UTF8(char_list(n));
        str_element=uint8(str_element);
        str(positions==n)={str_element};
    end
end
str=cell2mat(str);str=char(str);
end
function str=unicode_to_UTF16(unicode)
%Convert a single character to UTF-16 bytes.
%
%The value of the input is converted to binary and padded with 0 bits at the front of the string to
%fill all 'x' positions in the scheme.
%See https://en.wikipedia.org/wiki/UTF-16
%
% 1 word (U+0000 to U+D7FF and U+E000 to U+FFFF):
%  xxxxxxxx_xxxxxxxx
% 2 words (U+10000 to U+10FFFF):
%  110110xx_xxxxxxxx 110111xx_xxxxxxxx
if unicode<65536
    str=unicode;return
end
U=double(unicode)-65536;%convert to double for ML6.5
U=dec2bin(U,20);
str=bin2dec(['110110' U(1:10);'110111' U(11:20)]).';
end
function str=unicode_to_UTF8(unicode)
%Convert a single character to UTF-8 bytes.
%
%The value of the input is converted to binary and padded with 0 bits at the front of the string to
%fill all 'x' positions in the scheme.
%See https://en.wikipedia.org/wiki/UTF-8
if unicode<255
    str=unicode;return
end
persistent pers
if isempty(pers)
    pers=struct;
    pers.limits.lower=hex2dec({'0000','0080','0800', '10000'});
    pers.limits.upper=hex2dec({'007F','07FF','FFFF','10FFFF'});
    pers.scheme{2}='110xxxxx10xxxxxx';
    pers.scheme{2}=reshape(pers.scheme{2}.',8,2);
    pers.scheme{3}='1110xxxx10xxxxxx10xxxxxx';
    pers.scheme{3}=reshape(pers.scheme{3}.',8,3);
    pers.scheme{4}='11110xxx10xxxxxx10xxxxxx10xxxxxx';
    pers.scheme{4}=reshape(pers.scheme{4}.',8,4);
    for b=2:4
        pers.scheme_pos{b}=find(pers.scheme{b}=='x');
        pers.bits(b)=numel(pers.scheme_pos{b});
    end
end
bytes=find(pers.limits.lower<unicode & unicode<pers.limits.upper);
str=pers.scheme{bytes};
scheme_pos=pers.scheme_pos{bytes};
b=dec2bin(unicode,pers.bits(bytes));
str(scheme_pos)=b;
str=bin2dec(str.').';
end
function [unicode,isUTF8,assumed_UTF8]=UTF8_to_unicode(UTF8,print_to)
%Convert UTF-8 to the code points stored as uint32
%Plane 16 goes up to 10FFFF, so anything larger than uint16 will be able to hold every code point.
%
%If there a second output argument, this function will not return an error if there are encoding
%error. The second output will contain the attempted conversion, while the first output will
%contain the original input converted to uint32.
%
%The second input can be used to also print the error to a GUI element or to a text file.
if nargin<2,print_to=[];end
return_on_error= nargout==1 ;

UTF8=uint32(UTF8);
[assumed_UTF8,flag,ME]=UTF8_to_unicode_internal(UTF8,return_on_error);
if strcmp(flag,'success')
    isUTF8=true;
    unicode=assumed_UTF8;
elseif strcmp(flag,'error')
    isUTF8=false;
    if return_on_error
        error_(print_to,ME)
    end
    unicode=UTF8;%return input unchanged (apart from casting to uint32)
end
end
function [UTF8,flag,ME]=UTF8_to_unicode_internal(UTF8,return_on_error)

flag='success';
ME=struct('identifier','HJW:UTF8_to_unicode:notUTF8','message','Input is not UTF-8.');

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end

if any(UTF8>255)
    flag='error';
    if return_on_error,return,end
end

for bytes=4:-1:2
    val=bin2dec([repmat('1',1,bytes) repmat('0',1,8-bytes)]);
    multibyte=UTF8>=val & UTF8<256;%Exclude the already converted chars
    if any(multibyte)
        multibyte=find(multibyte);multibyte=multibyte(:).';
        if numel(UTF8)<(max(multibyte)+2)
            flag='error';
            if return_on_error,return,end
            multibyte( (multibyte+bytes-1)>numel(UTF8) )=[];
        end
        if ~isempty(multibyte)
            idx=bsxfun_plus(multibyte , (0:(bytes-1)).' );
            idx=idx.';
            multibyte=UTF8(idx);
        end
    else
        multibyte=[];
    end
    header_bits=[repmat('1',1,bytes-1) repmat('10',1,bytes)];
    header_locs=unique([1:(bytes+1) 1:8:(8*bytes) 2:8:(8*bytes)]);
    if numel(multibyte)>0
        multibyte=unique(multibyte,'rows');
        S2=mat2cell(multibyte,ones(size(multibyte,1),1),bytes);
        for n=1:numel(S2)
            bin=dec2bin(double(S2{n}))';
            %To view the binary data, you can use this: bin=bin(:)';
            %Remove binary header (3 byte example):
            %1110xxxx10xxxxxx10xxxxxx
            %    xxxx  xxxxxx  xxxxxx
            if ~strcmp(header_bits,bin(header_locs))
                %Check if the byte headers match the UTF8 standard
                flag='error';
                if return_on_error,return,end
                continue %leave unencoded
            end
            bin(header_locs)='';
            if ~isOctave
                S3=uint32(bin2dec(bin  ));
            else
                S3=uint32(bin2dec(bin.'));%Octave needs an extra transpose
            end
            %Perform actual replacement
            UTF8=PatternReplace(UTF8,S2{n},S3);
        end
    end
end
end
function warning_(options,varargin)
%Print a warning to the command window, a file and/or the String property of an object.
%The lastwarn state will be set if the warning isn't thrown with warning().
%The printed call trace omits this function, but the warning() call does not.
%
%The intention is to allow replacement of most warning(___) call with warning_(options,___). This
%does not apply to calls that query or set the warning state.
%
%options.con:         if true print warning to command window with warning()
%options.fid.boolean: if true print warning to file (options.fid.fid)
%options.obj.boolean: if true print warning to object (options.obj.obj)
%
%syntax:
%  warning_(options,msg)
%  warning_(options,msg,A1,...,An)
%  warning_(options,id,msg)
%  warning_(options,id,msg,A1,...,An)

if isempty(options),options=struct;end%allow empty input to revert to default
if ~isfield(options,'con'),options.con=false;end
if ~isfield(options,'fid'),options.fid.boolean=false;end
if ~isfield(options,'obj'),options.obj.boolean=false;end
if nargin==2 || ~isempty(strfind(varargin{1},'%')) % id can't contain a percent symbol
    %  warning_(options,msg,A1,...,An)
    [id,msg]=deal('',varargin{1});
    if nargin>3
        A1_An=varargin(2:end);
        msg=sprintf(msg,A1_An{:});
    end
else
    %  warning_(options,id,msg)
    %  warning_(options,id,msg,A1,...,An)
    [id,msg]=deal(varargin{1},varargin{2});
    if nargin>3
        A1_An=varargin(3:end);
        msg=sprintf(msg,A1_An{:});
    end
end

if options.con
    if ~isempty(id)
        warning(id,'%s',msg)
    else
        warning(msg)
    end
else
    if ~isempty(id)
        lastwarn(msg,id);
    else
        lastwarn(msg)
    end
end

if options.obj.boolean
    msg_=msg;while msg_(end)==10,msg_(end)=[];end%crop trailing newline
    if any(msg_==10)  % parse to cellstr and prepend warning
        msg_=regexp_outkeys(['Warning: ' msg_],char(10),'split'); %#ok<CHARTEN>
    else              % only prepend warning
        msg_=['Warning: ' msg_];
    end
    set(options.obj.obj,'String',msg_)
end

if options.fid.boolean
    skip_layers=2;%this function and the get_trace function
    trace=get_trace(skip_layers);
    fprintf(options.fid.fid,'Warning: %s\n%s',msg,trace);
end
end