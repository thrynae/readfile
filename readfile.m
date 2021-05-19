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
%  print_to_con : A logical that controls whether warnings and other output will be printed to the
%           command window. Errors can't be turned off. [default=true;] if either print_to_fid,
%           print_to_obj, or print_to_fcn is specified then [default=false]
%  print_to_fid : The file identifier where console output will be printed. Errors and warnings
%           will be printed including the call stack. You can provide the fid for the command
%           window (fid=1) to print warnings as text. Errors will be printed to the specified file
%           before being actually thrown. [default=[];]
%           If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the
%           effect of suppressing every output except errors.
%           This parameter does not affect warnings or errors during input parsing.
%           Array inputs are allowed.
%  print_to_obj : The handle to an object with a String property, e.g. an edit field in a GUI where
%           console output will be printed. Messages with newline characters (ignoring trailing
%           newlines) will be returned as a cell array. This includes warnings and errors, which
%           will be printed without the call stack. Errors will be written to the object before the
%           error is actually thrown. [default=[];]
%           If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the
%           effect of suppressing every output except errors.
%           This parameter does not affect warnings or errors during input parsing.
%           Array inputs are allowed.
% print_to_fcn : A struct with a function handle, anonymous function or inline function in the 'h'
%           field and optionally additional data in the 'data' field. The function should accept
%           three inputs: a char array (either 'warning' or 'error'), a struct with the message,
%           id, and stack, and the optional additional data. The function(s) will be run before the
%           error is actually thrown. [default=[];]
%           If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the
%           effect of suppressing every output except errors.
%           This parameter does not affect warnings or errors during input parsing.
%           Array inputs are allowed.
%  err_on_ANSI : If set to true, an error will be thrown when the input file is not recognized as
%           UTF-8 encoded. This should normally not be an issue, as ANSI files can be read as well
%           with this function. [default=false;]
%  EmptyLineRule : This contains a description of how empty lines should be handled. Lines that
%           only contain whitespace are considered empty as well, to conform to the behavior of
%           readlines (this therefore also depends on the Whitespace parameter). Valid values are
%           'read', 'skip', 'error', 'skipleading', and 'skiptrailing'.
%           The latter two are not available for readlines. Values can be entered as a scalar
%           string or as a char array. [default='read';]
%  WhitespaceRule : This contains a description of how should leading and trailing whitespace be
%           handled on each line. Depending on the value of the Whitespace parameter this is
%           equivalent to readlines. Valid values are 'preserve', 'trim', 'trimleading', and
%           'trimtrailing'. [default='preserve';]
%  LineEnding : This parameter determines which characters are considered line ending characters.
%           String arrays and cell arrays of char vectors are parsed by sprintf, with each element
%           being considered a line break. String scalars and character vectors are treated as
%           literal.
%           The default is {'\n','\r','\r\n'} meaning that \n\r is considered 2 line ends. This
%           will not be checked for any overlap and will be processed sequentially. The only is the
%           default, which will be sorted to {'\r\n','\n','\r'}. [default={'\n','\r','\r\n'};]
%  Whitespace : This parameter determines which characters are treated as whitespace for the
%           purposes of EmptyLineRule and WhitespaceRule. This should be a char vector or a scalar
%           string. Cell arrays of char vectors are parsed by sprintf and concatenated. Note that
%           the default for readlines is sprintf(' \b\t'), but in this function this is expanded.
%           [default=[8 9 28:32 160 5760 8192:8202 8239 8287 12288];]
%  UseReadlinesDefaults : Reproduce the default behavior of readlines as closely as possible. This
%           includes reproducing a bug which causes all characters that require 2 uint16 values to
%           encode in UTF-16 (everything outside the base multilingual plane, i.e. most emoji) to
%           be converted to char(26).
%           This will not convert the output to a string array. [default=false;]
%
% This function is aimed at providing a reliable method of reading a file. The backbone of this
% function is fread, supplemented by the fileread function. These work in slightly different ways
% and can be used under different circumstances. An attempt is made to detect the encoding (UTF-8
% or ANSI), apply the transcoding and returning the file as an n-by-1 cell array for files with
% n lines.
% You can redirect all outputs (errors only partially) to a file or a graphics object, or run a
% function based on the errors/warnings so you can more easily use this function in a GUI or allow
% it to write to a log file.
%
% Some input parameters can be used to mimic the readlines function, which was introduced in R2020a
% and returns a string vector instead of a cell array of character vectors.
%
% The test for being UTF-8 can fail. For files with chars in the 128:255 range, the test will often
% determine the encoding correctly, but it might fail, especially for files with encoding errors.
% Online files are much more limited than offline files. To avoid this the files are downloaded to
% tempdir() and deleted after reading. To avoid this the files are downloaded to tempdir() and
% deleted after reading. An additional fallback reads online files with webread/urlread, although
% this will often result in an incorrect output. This should only be relevant if there is no write
% access to the tempdir().
%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%|                                                                         |%
%|  Version: 4.0.0                                                         |%
%|  Date:    2021-05-19                                                    |%
%|  Author:  H.J. Wisselink                                                |%
%|  Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 ) |%
%|  Email = 'h_j_wisselink*alumnus_utwente_nl';                            |%
%|  Real_email = regexprep(Email,{'*','_'},{'@','.'})                      |%
%|                                                                         |%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%
% Compatibility considerations:
% Tested on several versions of Matlab (ML 6.5 and onward) and Octave (4.4.1 and onward), and on
% multiple operating systems (Windows/Ubuntu/MacOS). For the full test matrix, see the HTML doc.
% - The size of the char arrays may be different between Octave and Matlab. This is because Matlab
%   encodes characters internally with UTF-16, which means all 'normal' characters only take up a
%   single 16 bit value. A doc page seems to suggest Matlab uses UTF-8 to encode chars, but appears
%   to only be true for file interactions. If you want to include higher Unicode code points (e.g.
%   most emoji), some characters will require 2 elements in a char array. Octave use UTF-8 to
%   encode chars, but chars with values 128-255 are supported 'by accident'. This might change at
%   some point, but switching Octave to UTF-16 would require a lot of work, with the only
%   fundamental benefit being that size functions will return the same results between Matlab and
%   Octave. Judging by a discussion in the Octave bug tracker, I doubt this change will ever
%   happen.
% - It is therefore important to remember that a scalar char is not guaranteed to be a single
%   Unicode character, and that a single Unicode character is not guaranteed to be a single glyph. 
% - The readlines function was introduced in R2020b. It doesn't read to a cell of chars, but to a
%   string vector. The documentation implies that these two functions are functionally equivalent
%   (apart from that difference), but it seems to fail for characters beyond the BMP (Basic
%   Multilingual Plane). That means most emoji will fail. A future version of readlines might
%   correct this. When this bug is corrected
%   isequal(cellstr(readlines(filename)),readfile(filename)) should return true for all files.
%   Since R2021a readlines also supports reading online files.
% - Incorrect reading of files should only occur if the download to a temporary location fails.
%   (NB: this should be a rare occurence) Modern releases of Matlab (>=R2015a) are expected to read
%   every file correctly, except for ANSI files containing special characters. GNU Octave has
%   trouble with many ANSI files. Older releases of Matlab have the same results as Octave for ANSI
%   files, but also have issues with some UTF-8 files. Interestingly, R13 (v6.5) performs better on
%   ANSI files, but worse on UTF-8.

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
    error('HJW:readfile:nargout','Incorrect number of output argument.')
end
[success,opts,ME]=readfile_parse_inputs(filename,varargin{:});
if ~success
    rethrow(ME)
else
    [print_2,legacy,UseURLread,err_on_ANSI,EmptyLineRule,Whitespace,LineEnding,...
        FailMultiword_UTF16,WhitespaceRule]=...
        deal(opts.print_2__options,opts.legacy,opts.UseURLread,opts.err_on_ANSI,...
        opts.EmptyLineRule,opts.Whitespace,opts.LineEnding,opts.FailMultiword_UTF16,...
        opts.WhitespaceRule);
end

if isa(filename,'string'),filename=char(filename);end
if numel(filename)>=8 && ( strcmpi(filename(1:7),'http://') || strcmpi(filename(1:8),'https://') )
    if ~legacy.allows_https && strcmpi(filename(1:8),'https://')
        warning_(print_2,'HJW:readfile:httpsNotSupported',...
            ['This implementation of urlread probably doesn''t allow https requests.',char(10),...
            'The next lines of code will probably result in an error.']) %#ok<CHARTEN>
    end
    str=readfile_from_URL(filename,UseURLread,print_2,LineEnding,err_on_ANSI);
    if isa(str,'cell') %file was read from temporary downloaded version
        data=str;
    else
        %This means the download failed. Some files will not work.
        invert=true;
        str=convert_from_codepage(str,invert);
        try ME=[]; %#ok<NASGU>
            [ii,isUTF8,converted]=UTF8_to_unicode(str); %#ok<ASGLU>
        catch ME;if isempty(ME),ME=lasterror;end %#ok<LERR>
            if strcmp(ME.identifier,'HJW:UTF8_to_unicode:notUTF8')
                isUTF8=false;
            else
                error_(print_2,ME)
            end
        end
        if isUTF8
            str=unicode_to_char(converted);
        end
        if isa(LineEnding,'double') && isempty(LineEnding)
            data=char2cellstr(str);
        else
            data=char2cellstr(str,LineEnding);
        end
    end
else
    data=readfile_from_file(filename,LineEnding,print_2,err_on_ANSI);
end

%Determine the location of whitespace, but only if relevant.
if ~strcmp(EmptyLineRule,'read') || ~strcmp(WhitespaceRule,'preserve')
    L=cellfun('isempty',data);
    for n=find(~L).'
        % The cellfun call will only find completely empty lines, while readlines implicitly
        % considers lines with only whitespace empty.
        tmp=ismember(data{n},Whitespace);
        L(n)=all(tmp);
        if ~strcmp(WhitespaceRule,'preserve')
            % If there is only whitespace, take a shortcut by wiping the line now.
            if L(n),data{n}='';continue,end
            % If the first and last chars are whitespace, triming will have no effect.
            if ~tmp(1) && ~tmp(end),continue,end
            %Find the indices of non-whitespace.
            switch WhitespaceRule
                case 'trim'
                    inds=find(~tmp);inds=inds([1 end]);
                case 'trimleading'
                    %Use findND to extend the syntax for old Matlab releases.
                    inds=[findND(~tmp,1) numel(tmp)];
                case 'trimtrailing'
                    %Use findND to extend the syntax for old Matlab releases.
                    inds=[1 findND(~tmp,1,'last')];
            end
            data{n}=data{n}(inds(1):inds(2));
        end
    end
end
if ~strcmp(EmptyLineRule,'read')
    switch EmptyLineRule
        %To allow the expanded syntax for find(), the findND() function is used instead, as that
        %extends the syntax for find() on old releases of Matlab.
        case 'skip'
            data(L)=[];
        case 'error'
            if any(L)
                error_(print_2,'HJW:readfile:EmptyLinesRuleError',...
                    'Unexpected empty line detected on row %d',findND(L,1))
            end
        case 'skipleading'
            if L(1)
                ind=1:(findND(~L,1,'first')-1);
                data(ind)=[];
            end
        case 'skiptrailing'
            if L(end)
                ind=(1+findND(~L,1,'last')):numel(L);
                data(ind)=[];
            end
    end
end
persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
if FailMultiword_UTF16
    %R2020b and R2021a fail for multiword UTF16 characters, rendering them as char(26). To keep
    %complete equivalence, that behavior is replicated here.
    %The bit-pattern is 110110xx_xxxxxxxx 110111xx_xxxxxxxx, so we can simply detect any value
    %between 55296 and 56319. For Octave we can check if there are 4-byte characters.
    for n=1:numel(data)
        if isOctave
            if any(data{n}>=240)
                %Now we need to properly convert to UTF-32, replace by 26 and convert back.
                data{n}=replace_multiword_UTF16_by_26(data{n});
            end
        else
            if any(data{n}>=55296 & data{n}<=56319)
                %Now we need to properly convert to UTF-32, replace by 26 and convert back.
                data{n}=replace_multiword_UTF16_by_26(data{n});
            end
        end
    end
end
end
function out=replace_multiword_UTF16_by_26(in)
%Replace all multiword UTF-16 (i.e. U+10000 to U+10FFFF) with char(26)
persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
if isOctave
    unicode=UTF8_to_unicode(in);
else
    unicode=UTF16_to_unicode(in);
end
%Perform replacement.
unicode(unicode>=65536)=26;
%Convert back to proper encoding
if isOctave
    out=char(unicode_to_UTF8(unicode));
else
    out=char(unicode_to_UTF16(unicode));
end
end
function out=bsxfun_plus(in1,in2)
%Implicit expansion for plus(), but without any input validation.
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
function c=char2cellstr(str,LineEnding)
%Split char or uint32 vector to cell (1 cell element per line). Default splits are for CRLF/CR/LF.
%The input data type is preserved.
%
%Since the largest valid Unicode codepoint is 0x10FFFF (i.e. 21 bits), all values will fit in an
%int32 as well. This is used internally to deal with different newline conventions.
%
%The second input is a cellstr containing patterns that will be considered as newline encodings.
%This will not be checked for any overlap and will be processed sequentially.

returnChar=isa(str,'char');
str=int32(str);%convert to signed, this should not crop any valid Unicode codepoints.

if nargin<2
    %Replace CRLF, CR, and LF with -10 (in that order). That makes sure that all valid encodings of
    %newlines are replaced with the same value. This should even handle most cases of files that
    %mix the different styles, even though such mixing should never occur in a properly encoded
    %file. This considers LFCR as two line endings.
    if any(str==13)
        str=PatternReplace(str,int32([13 10]),int32(-10));
        str(str==13)=-10;
    end
    str(str==10)=-10;
else
    for n=1:numel(LineEnding)
        str=PatternReplace(str,int32(LineEnding{n}),int32(-10));
    end
end

%Split over newlines.
newlineidx=[0 find(str==-10) numel(str)+1];
c=cell(numel(newlineidx)-1,1);
for n=1:numel(c)
    s1=(newlineidx(n  )+1);
    s2=(newlineidx(n+1)-1);
    c{n}=str(s1:s2);
end

%Return to the original data type.
if returnChar
    for n=1:numel(c),c{n}=  char(c{n});end
else
    for n=1:numel(c),c{n}=uint32(c{n});end
end
end
function str=convert_from_codepage(str,inverted)
%Convert from the Windows-1252 codepage.
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
%Apart from controlling the way an error is written, you can also run a specific function. The
%'fcn' field of the options must be a struct (scalar or array) with two fields: 'h' with a function
%handle, and 'data' with arbitrary data passed as third input. These functions will be run with
%'error' as first input. The second input is a struct with identifier, message, and stack as
%fields. This function will be run with feval (meaning the function handles can be replaced with
%inline functions or anonymous functions).
%
%The intention is to allow replacement of every error(___) call with error_(options,___).
%
% NB: the error trace that is written to a file or object may differ from the trace displayed by
% calling the builtin error function. This was only observed when evaluating code sections.
%
%options.boolean.con: if true throw error with rethrow()
%options.fid:         file identifier for fprintf (array input will be indexed)
%options.boolean.fid: if true print error to file
%options.obj:         handle to object with String property (array input will be indexed)
%options.boolean.obj: if true print error to object (options.obj)
%options.fcn          struct (array input will be indexed)
%options.fcn.h:       handle of function to be run
%options.fcn.data:    data passed as third input to function to be run (optional)
%options.boolean.fnc: if true the function(s) will be run
%
%syntax:
%  error_(options,msg)
%  error_(options,msg,A1,...,An)
%  error_(options,id,msg)
%  error_(options,id,msg,A1,...,An)
%  error_(options,ME)               %equivalent to rethrow(ME)
%
%examples options struct:
%  % Write to a log file:
%  opts=struct;opts.fid=fopen('log.txt','wt');
%  % Display to a status window and bypass the command window:
%  opts=struct;opts.boolean.con=false;opts.obj=uicontrol_object_handle;
%  % Write to 2 log files:
%  opts=struct;opts.fid=[fopen('log2.txt','wt') fopen('log.txt','wt')];

persistent this_fun
if isempty(this_fun),this_fun=func2str(@error_);end

%Parse options struct.
if isempty(options),options=struct;end%allow empty input to revert to default
options=parse_warning_error_redirect_options(options);
[id,msg,stack,trace]=parse_warning_error_redirect_inputs(varargin{:});
ME=struct('identifier',id,'message',msg,'stack',stack);

%Print to object.
if options.boolean.obj
    msg_=msg;while msg_(end)==10,msg_(end)='';end%Crop trailing newline.
    if any(msg_==10)  % Parse to cellstr and prepend 'Error: '.
        msg_=char2cellstr(['Error: ' msg_]);
    else              % Only prepend 'Error: '.
        msg_=['Error: ' msg_];
    end
    for OBJ=options.obj(:).'
        try set(OBJ,'String',msg_);catch,end
    end
end

%Print to file.
if options.boolean.fid
    for FID=options.fid(:).'
        try fprintf(FID,'Error: %s\n%s',msg,trace);catch,end
    end
end

%Run function.
if options.boolean.fcn
    if ismember(this_fun,{stack.name})
        %To prevent an infinite loop, trigger an error.
        error('prevent recursion')
    end
    for FCN=options.fcn(:).'
        if isfield(FCN,'data')
            try feval(FCN.h,'error',ME,FCN.data);catch,end
        else
            try feval(FCN.h,'error',ME);catch,end
        end
    end
end

%Actually throw the error.
rethrow(ME)
end
function varargout=findND(X,varargin)
%Find non-zero elements in ND-arrays. Replicates all behavior from find.
% The syntax is equivalent to the built-in find, but extended to multi-dimensional input.
%
% [...] = findND(X,K) returns at most the first K indices. K must be a positive scalar of any type.
%
% [...] = findND(X,K,side) returns either the first K or the last K indices. The input side  must
% be a char, either 'first' or 'last'. The default behavior is 'first'.
%
% [I1,I2,I3,...,In] = findND(X,...) returns indices along all the dimensions of X.
%
% [I1,I2,I3,...,In,V] = findND(X,...) returns indices along all the dimensions of X, and
% additionally returns a vector containing the values.
%
% Note for Matlab 6.5:
% The syntax with more than one input is present in the online doc for R14 (Matlab 7.0), so this
% might be the latest release without support for this syntax.
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
% Version: 1.2.1
% Date:    2020-07-06
% Author:  H.J. Wisselink
% Licence: CC by-nc-sa 4.0 ( https://creativecommons.org/licenses/by-nc-sa/4.0 )
% Email = 'h_j_wisselink*alumnus_utwente_nl';
% Real_email = regexprep(Email,{'*','_'},{'@','.'})

%Parse inputs
if ~(isnumeric(X) || islogical(X)) || numel(X)==0
    error('HJW:findND:FirstInput',...
        'Expected first input (X) to be a non-empty numeric or logical array.')
end
switch nargin
    case 1 %[...] = findND(X);
        side='first';
        K=inf;
    case 2 %[...] = findND(X,K);
        side='first';
        K=varargin{1};
        if ~(isnumeric(K) || islogical(K)) || numel(K)~=1 || any(K<0)
            error('HJW:findND:SecondInput',...
                'Expected second input (K) to be a positive numeric or logical scalar.')
        end
    case 3 %[...] = FIND(X,K,'first');
        K=varargin{1};
        if ~(isnumeric(K) || islogical(K)) || numel(K)~=1 || any(K<0)
            error('HJW:findND:SecondInput',...
                'Expected second input (K) to be a positive numeric or logical scalar.')
        end
        side=varargin{2};
        if ~isa(side,'char') || ~( strcmpi(side,'first') || strcmpi(side,'last'))
            error('HJW:findND:ThirdInput','Third input must be either ''first'' or ''last''.')
        end
        side=lower(side);
    otherwise
        error('HJW:findND:InputNumber','Incorrect number of inputs.')
end

%parse outputs
nDims=length(size(X));
%allowed outputs: 0, 1, nDims, nDims+1
if nargout>1 && nargout<nDims
    error('HJW:findND:Output','Incorrect number of output arguments.')
end

persistent OldSyntax
if isempty(OldSyntax)
    OldSyntax=ifversion('<',7,'Octave','<',3);
end

varargout=cell(nargout,1);
if OldSyntax
    %The find(X,k,side) syntax was introduced between 6.5 and 7.
    if nargout>nDims
        [ind,col_index_equal_to_one,val]=find(X(:));%#ok no tilde pre-R2009b
        %X(:) converts X to a column vector. Treating X(:) as a matrix forces val to be the actual
        %value, instead of the column index.
        if length(ind)>K
            if strcmp(side,'first') %Select first K outputs.
                ind=ind(1:K);
                val=val(1:K);
            else                    %Select last K outputs.
                ind=ind((end-K+1):end);
                val=val((end-K+1):end);
            end
        end
        [varargout{1:(end-1)}] = ind2sub(size(X),ind);
        varargout{end}=val;
    else
        ind=find(X);
        if length(ind)>K
            if strcmp(side,'first')
                %Select first K outputs.
                ind=ind(1:K);
            else
                %Select last K outputs.
                ind=ind((end-K):end);
            end
        end
        [varargout{:}] = ind2sub(size(X),ind);
    end
else
    if nargout>nDims
        [ind,col_index_equal_to_one,val]=find(X(:),K,side);%#ok<ASGLU>
        %X(:) converts X to a column vector. Treating X(:) as a matrix forces val to be the actual
        %value, instead of the column index.
        [varargout{1:(end-1)}] = ind2sub(size(X),ind);
        varargout{end}=val;
    else
        ind=find(X,K,side);
        [varargout{:}] = ind2sub(size(X),ind);
    end
end
end
function [str,stack]=get_trace(skip_layers,stack)
if nargin==0,skip_layers=1;end
if nargin<2, stack=dbstack;end
stack(1:skip_layers)=[];

%Parse the ML6.5 style of dbstack (the name field includes full file location).
if ~isfield(stack,'file')
    for n=1:numel(stack)
        tmp=stack(n).name;
        if strcmp(tmp(end),')')
            %Internal function.
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

%Parse Octave style of dbstack (the file field includes full file location).
persistent IsOctave,if isempty(IsOctave),IsOctave=exist('OCTAVE_VERSION','builtin');end
if IsOctave
    for n=1:numel(stack)
        [ignore,stack(n).file]=fileparts(stack(n).file); %#ok<ASGLU>
    end
end

%Create the char array with a (potentially) modified stack.
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
% ifversion('<',0,'Octave','>=',6) returns true only on Octave 6 and higher
%
% The conversion is based on a manual list and therefore needs to be updated manually, so it might
% not be complete. Although it should be possible to load the list from Wikipedia, this is not
% implemented.
%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%|                                                                         |%
%|  Version: 1.0.6                                                         |%
%|  Date:    2021-03-11                                                    |%
%|  Author:  H.J. Wisselink                                                |%
%|  Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 ) |%
%|  Email = 'h_j_wisselink*alumnus_utwente_nl';                            |%
%|  Real_email = regexprep(Email,{'*','_'},{'@','.'})                      |%
%|                                                                         |%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%
% Tested on several versions of Matlab (ML 6.5 and onward) and Octave (4.4.1 and onward), and on
% multiple operating systems (Windows/Ubuntu/MacOS). For the full test matrix, see the HTML doc.
% Compatibility considerations:
% - This is expected to work on all releases.

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
        'R13' 605;'R13SP1' 605;'R13SP2' 605;'R14' 700;'R14SP1' 700;'R14SP2' 700;
        'R14SP3' 701;'R2006a' 702;'R2006b' 703;'R2007a' 704;'R2007b' 705;
        'R2008a' 706;'R2008b' 707;'R2009a' 708;'R2009b' 709;'R2010a' 710;
        'R2010b' 711;'R2011a' 712;'R2011b' 713;'R2012a' 714;'R2012b' 800;
        'R2013a' 801;'R2013b' 802;'R2014a' 803;'R2014b' 804;'R2015a' 805;
        'R2015b' 806;'R2016a' 900;'R2016b' 901;'R2017a' 902;'R2017b' 903;
        'R2018a' 904;'R2018b' 905;'R2019a' 906;'R2019b' 907;'R2020a' 908;
        'R2020b' 909;'R2021a' 910};
end

if octave
    if nargin==2
        warning('HJW:ifversion:NoOctaveTest',...
            ['No version test for Octave was provided.',char(10),...
            'This function might return an unexpected outcome.']) %#ok<CHARTEN>
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
    elseif nargin==4
        % Undocumented shorthand syntax: skip the 'Octave' argument.
        [test,v]=deal(Oct_flag,Oct_test);
        % Convert 4.1 to 401.
        v=0.1*v+0.9*fix(v);v=round(100*v);
    else
        [test,v]=deal(Oct_test,Oct_ver);
        % Convert 4.1 to 401.
        v=0.1*v+0.9*fix(v);v=round(100*v);
    end
else
    % Convert R notation to numeric and convert 9.1 to 901.
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
function [id,msg,stack,trace]=parse_warning_error_redirect_inputs(varargin)
if nargin==1
    %  error_(options,msg)
    %  error_(options,ME)
    if isa(varargin{1},'struct') || isa(varargin{1},'MException')
        ME=varargin{1};
        try
            stack=ME.stack;%Use the original call stack if possible.
            trace=get_trace(0,stack);
        catch
            [trace,stack]=get_trace(3);
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
        [trace,stack]=get_trace(3);
        [id,msg]=deal('',varargin{1});
    end
else
    [trace,stack]=get_trace(3);
    if ~isempty(strfind(varargin{1},'%')) %The id can't contain a percent symbol.
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
end
function options=parse_warning_error_redirect_options(options)
%Fill the struct:
%options.boolean.con (this field is ignored in error_)
%options.boolean.fid
%options.boolean.obj
%options.boolean.fcn
if ~isfield(options,'boolean'),options.boolean=struct;end
if ~isfield(options.boolean,'con') || isempty(options.boolean.con)
    options.boolean.con=false;
end
if ~isfield(options.boolean,'fid') || isempty(options.boolean.fid)
    options.boolean.fid=isfield(options,'fid');
end
if ~isfield(options.boolean,'obj') || isempty(options.boolean.obj)
    options.boolean.obj=isfield(options,'obj');
end
if ~isfield(options.boolean,'fcn') || isempty(options.boolean.fcn)
    options.boolean.fcn=isfield(options,'fcn');
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
        %Now k contains the indices of the beginning of each match.
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
        k=k(:);%Enforce direction.
        remove=(n+1):numel(pattern);
        idx=bsxfun_plus(k,remove-1);
        out(idx(:))=[];
    end
end
end
function str=readfile_from_file(filename,LineEnding,print_2,err_on_ANSI)
persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
persistent ME_file_access_FormatSpec
if isempty(ME_file_access_FormatSpec)
    if isOctave,runtime='Octave';else,runtime='Matlab';end
    ME_file_access_FormatSpec=sprintf(['%s could not read the file %%s.\n',...
        'The file doesn''t exist or is not readable.\n',...
        '(Note that for online files, only http and https is supported.)'],runtime);
end
ME_file_access=struct('identifier','HJW:readfile:ReadFail','message',...
        sprintf(ME_file_access_FormatSpec,filename));

fid=fopen(filename,'rb');
if fid<0,error_(print_2,ME_file_access),end
data=fread(fid,'uint8');
fclose(fid);
data=data.';
try ME=[]; %#ok<NASGU>
    isUTF8=true;
    converted=UTF8_to_unicode(data);
catch ME;if isempty(ME),ME=lasterror;end %#ok<LERR>
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
    else %This assumes Mac will work the same as Ubuntu.
        if isUTF8
            str=converted;
        else
            str=convert_from_codepage(data);
        end
    end
end

%Remove UTF BOM (U+FEFF) from text.
if numel(str)>=1 && double(str(1))==65279,str(1)=[];end
%Convert back to a char and split to a cellstr.
str=unicode_to_char(str);
if isa(LineEnding,'double') && isempty(LineEnding)
    str=char2cellstr(str);
else
    str=char2cellstr(str,LineEnding);
end
end
function str=readfile_from_URL(url,UseURLread,print_to,LineEnding,err_on_ANSI)
%Read the contents of a file to a char array.
%
%Attempt to download to the temp folder, read the file, then delete it.
%If that fails, read to a char array with urlread/webread.
try
    RevertToUrlread=false;%in case the saving+reading fails
    %Generate a random file name in the temp folder.
    fn=tmpname('readfile_from_URL_tmp_','.txt');
    try
        %Try to download (with 'raw' as ContentType to prevent parsing of XML/JSON/etc by websave).
        if UseURLread,fn=urlwrite(url,fn); %#ok<URLWR>
        else,         fn= websave(fn,url,weboptions('ContentType','raw'));end
        
        %Try to read
        str=readfile_from_file(fn,LineEnding,print_to,err_on_ANSI);
    catch
        RevertToUrlread=true;
    end
    
    %Delete the temp file
    try if exist(fn,'file'),delete(fn);end,catch,end
    
    if RevertToUrlread,error('revert to urlread'),end
catch
    %Read to a char array and let these functions throw an error in case of HTML errors and/or
    %missing connectivity.
    try ME=[]; %#ok<NASGU>
        %Use 'raw' as ContentType to prevent parsing of XML/JSON/etc by webread.
        if UseURLread,str=urlread(url);else%#ok<URLRD>
            str=webread(url,weboptions('ContentType','raw'));end 
    catch ME;if isempty(ME),ME=lasterror;end %#ok<LERR>
        error_(print_to,ME)
    end
end
end
function [success,options,ME]=readfile_parse_inputs(filename,varargin)
%Parse the inputs of the readfile function
% It returns a success flag, the parsed options, and an ME struct.
% As input, the options should either be entered as a struct or as Name,Value pairs. Missing fields
% are filled from the default.

%Pre-assign outputs.
success=false;
options=struct;
ME=struct('identifier','','message','');

%Test the required input.

if ... %Enumerate all possible incorrect inputs.                   %The first input
        ~( isa(filename,'char') || isa(filename,'string') ) || ... %must be either char or string
        ( isa(filename,'string') && numel(filename)~=1 )    || ... %if string, must be scalar
        ( isa(filename,'char')   && numel(filename)==0 )           %if char, must be non-empty.
    ME.identifier='HJW:readfile:IncorrectInput';
    ME.message='The file name must be a non-empty char or a scalar string.';
    return
end

persistent default print_2__default_options
if isempty(default)
    %The regexp split option was introduced in R2007b.
    legacy.split = ifversion('<','R2007b','Octave','<',4);
    %Change this line when Octave does support https.
    legacy.allows_https=ifversion('>',0,'Octave','<',0);
    default.legacy=legacy;
    %Test if either webread(), websave(), or weboptions() are missing.
    try no_webread=isempty(which(func2str(@webread   )));catch,no_webread=true;end
    try no_websave=isempty(which(func2str(@websave   )));catch,no_websave=true;end
    try no_webopts=isempty(which(func2str(@weboptions)));catch,no_webopts=true;end
    default.UseURLread= no_webread || no_websave || no_webopts;
    
    print_2__default_options=struct;
    print_2__default_options.print_to_con=true;
    print_2__default_options.print_to_fid=[];
    print_2__default_options.print_to_obj=[];
    print_2__default_options.print_to_fcn=[];
    default.print_2__options=validate_print_to__options(print_2__default_options,ME);
    
    default.err_on_ANSI=false;
    %R2020b has a bug where readlines fails for chars outside the BMP (e.g. most emoji).
    default.FailMultiword_UTF16=false;
    default.EmptyLineRule='read';
    %The Whitespace parameter contains most characters reported by isspace, plus delete characters
    %and no break spaces. This is different from the default for readlines.
    %To make sure all these code points are encoded in char correctly, we need to use
    %unicode_to_char. The reason for this is that Octave uses UTF-8.
    default.Whitespace=unicode_to_char([8 9 28:32 160 5760 8192:8202 8239 8287 12288]);
    default.DefaultLineEnding=true;
    default.LineEnding=[];%(equivalent to {'\r\n','\n','\r'}, the order matters for char2cellstr)
    default.WhitespaceRule='preserve';
    
    default.UseReadlinesDefaults=false;
    default.ReadlinesDefaults.FailMultiword_UTF16=true;
    default.ReadlinesDefaults.Whitespace=sprintf(' \b\t');
    %Fill any missing fields.
    fn=fieldnames(default);
    for k=1:numel(fn)
        if ~isfield(options,fn(k)),default.ReadlinesDefaults.(fn{k})=default.(fn{k});end
    end
end
%The required inputs are checked, so now we need to return the default options if there are no
%further inputs.
if nargin==1
    options=default;
    success=true;
    return
end

%Test the optional inputs.
struct_input=   nargin==2        && isa(varargin{1},'struct');
NameValue_input=mod(nargin,2)==1 && all(...
    cellfun('isclass',varargin(1:2:end),'char'  ) | ...
    cellfun('isclass',varargin(1:2:end),'string')   );
if ~( struct_input || NameValue_input )
    ME.message=['The second input (options) is expected to be either a struct, ',char(10),...
        'or consist of Name,Value pairs.']; %#ok<CHARTEN>
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
%Do some special parsing for the print_2__options
print_2__replace_default_options=false;print_2__options=print_2__default_options;
%Create a copy of the defaults so they can be overwritten by the ReadlinesDefaults.
default__copy=default;
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
            options.err_on_ANSI=item;
        case 'print_to_fid'
            print_2__replace_default_options=true;
            print_2__options.print_to_fid=item;
        case 'print_to_obj'
            print_2__replace_default_options=true;
            print_2__options.print_to_obj=item;
        case 'print_to_fcn'
            print_2__replace_default_options=true;
            print_2__options.print_to_fcn=item;
        case 'print_to_con'
            print_2__replace_default_options=true;
            print_2__options.print_to_con=item;
        case 'EmptyLineRule'
            if isa(item,'string')
                if numel(item)~=1,item=[]; % This will trigger an error.
                else,item=char(item);end   % Convert a scalar string to char.
            end
            if isa(item,'char'),item=lower(item);end
            if ~isa(item,'char') || ...
                    ~ismember(item,{'read','skip','error','skipleading','skiptrailing'})
                ME.message='EmptyLineRule must be a char or string with a specific value.';
                return
            end
            options.EmptyLineRule=item;
        case 'Whitespace'
            %Cellstr input is converted to a char array with sprintf.
            try
                switch class(item)
                    case 'string'
                        if numel(item)~=1,error('trigger error'),end
                        item=char(item);
                    case 'cell'
                        for n=1:numel(item),item{n}=sprintf(item{n});end
                        item=horzcat(item{:});
                    case 'char'
                        %Nothing to check or do here.
                    otherwise
                        error('trigger error')
                end
                options.Whitespace=item;
            catch
                ME.message=['The Whitespace parameter must be a char vector, string scalar or ',...
                    'cellstr.\nA cellstr input must be parsable by sprintf.'];
                return
            end
        case 'WhitespaceRule'
            if isa(item,'string')
                if numel(item)~=1,item=[]; % This will trigger an error.
                else,item=char(item);end   % Convert a scalar string to char.
            end
            if isa(item,'char'),item=lower(item);end
            if ~isa(item,'char') || ...
                    ~ismember(item,{'preserve','trim','trimleading','trimtrailing'})
                ME.message='WhitespaceRule must be a char or string with a specific value.';
                return
            end
            options.WhitespaceRule=item;
        case 'LineEnding'
            %character vector  - literal
            %string scalar  - literal
            %cell array of character vectors  - parse by sprintf
            %string array  - parse by sprintf
            err=false;
            if isa(item,'string')
                item=cellstr(item);
                if numel(item)==1,item=item{1};end % Convert scalar string to char.
            end
            if isa(item,'cell')
                try for n=1:numel(item),item{n}=sprintf(item{n});end,catch,err=true;end
            elseif isa(item,'char')
                item={item};% Wrap char in a cell.
            else
                err=true; % This catches [] as well, while iscellstr wouldn't.
            end
            if err || ~iscellstr(item)
                ME.message=['The LineEnding parameter must be a char vector, a string or a ',...
                    'cellstr.\nA cellstr or string vector input must be parsable by sprintf.'];
                return
            end
            if isequal(item,{char(10) char(13) char([13 10])}) %#ok<CHARTEN>
                options.LineEnding=[];
            else
                options.LineEnding=item;
            end
        case 'UseReadlinesDefaults'
            [passed,item]=test_if_scalar_logical(item);
            if ~passed
                ME.message='UseReadlinesDefaults should be either true or false';
                return
            end
            options.UseReadlinesDefaults=item;
            if options.UseReadlinesDefaults
                default__copy=default.ReadlinesDefaults;
            end
    end
end

if print_2__replace_default_options
    ME.identifier='HJW:readfile:incorrect_input_opt_print_to_';
    [item,ME]=validate_print_to__options(print_2__options,ME);
    if isempty(item),return,end
    options.print_2__options=item;
else
    %If none of them were set, we can use the defaults.
    options.print_2__options=default__copy.print_2__options;
end

%Fill any missing fields.
fn=fieldnames(default__copy);
for k=1:numel(fn)
    if ~isfield(options,fn(k))
        options.(fn{k})=default__copy.(fn{k});
    end
end
success=true;ME=[];
end
function [isLogical,val]=test_if_scalar_logical(val)
%Test if the input is a scalar logical or convertible to it.
%The char and string test are not case sensitive.
%(use the first output to trigger an input error, use the second as the parsed input)
%
% Allowed values:
%- true or false
%- 1 or 0
%- 'on' or 'off'
%- matlab.lang.OnOffSwitchState.on or matlab.lang.OnOffSwitchState.off
%- 'enable' or 'disable'
%- 'enabled' or 'disabled'
persistent states
if isempty(states)
    states={true,false;...
        1,0;...
        'on','off';...
        'enable','disable';...
        'enabled','disabled'};
    try
        states(end+1,:)=eval('{"on","off"}');
    catch
    end
end
isLogical=true;
try
    if isa(val,'char') || isa(val,'string')
        try val=lower(val);catch,end
    end
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
function str=unicode_to_char(unicode,encode_as_UTF16)
%Encode Unicode code points with UTF-16 on Matlab and UTF-8 on Octave.
%Input is either implicitly or explicitly converted to a row-vector.

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
if nargin==1
    encode_as_UTF16=~isOctave;
end
if encode_as_UTF16
    if all(unicode<65536)
        str=uint16(unicode);
        str=reshape(str,1,numel(str));%Convert explicitly to a row-vector.
    else
        %Encode as UTF-16.
        [char_list,ignore,positions]=unique(unicode); %#ok<ASGLU>
        str=cell(1,numel(unicode));
        for n=1:numel(char_list)
            str_element=unicode_to_UTF16(char_list(n));
            str_element=uint16(str_element);
            str(positions==n)={str_element};
        end
        str=cell2mat(str);
    end
    if ~isOctave
        str=char(str);%Conversion to char could trigger a conversion range error in Octave.
    end
else
    if all(unicode<128)
        str=char(unicode);
        str=reshape(str,1,numel(str));%Convert explicitly to a row-vector.
    else
        %Encode as UTF-8
        [char_list,ignore,positions]=unique(unicode); %#ok<ASGLU>
        str=cell(1,numel(unicode));
        for n=1:numel(char_list)
            str_element=unicode_to_UTF8(char_list(n));
            str_element=uint8(str_element);
            str(positions==n)={str_element};
        end
        str=cell2mat(str);
        str=char(str);
    end
end
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
U=double(unicode)-65536;%Convert to double for ML6.5.
U=dec2bin(U,20);
str=bin2dec(['110110' U(1:10);'110111' U(11:20)]).';
end
function str=unicode_to_UTF8(unicode)
%Convert a single character to UTF-8 bytes.
%
%The value of the input is converted to binary and padded with 0 bits at the front of the string to
%fill all 'x' positions in the scheme.
%See https://en.wikipedia.org/wiki/UTF-8
if unicode<128
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
bytes=find(pers.limits.lower<=unicode & unicode<=pers.limits.upper);
str=pers.scheme{bytes};
scheme_pos=pers.scheme_pos{bytes};
b=dec2bin(unicode,pers.bits(bytes));
str(scheme_pos)=b;
str=bin2dec(str.').';
end
function unicode=UTF16_to_unicode(UTF16)
%Convert UTF-16 to the code points stored as uint32
%
%See https://en.wikipedia.org/wiki/UTF-16
%
% 1 word (U+0000 to U+D7FF and U+E000 to U+FFFF):
%  xxxxxxxx_xxxxxxxx
% 2 words (U+10000 to U+10FFFF):
%  110110xx_xxxxxxxx 110111xx_xxxxxxxx

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
UTF16=uint32(UTF16);

multiword= UTF16>55295 & UTF16<57344; %0xD7FF and 0xE000
if ~any(multiword)
    unicode=UTF16;return
end

word1= find( UTF16>=55296 & UTF16<=56319 );
word2= find( UTF16>=56320 & UTF16<=57343 );
try
    d=word2-word1;
    if any(d~=1)
        error('trigger error')
    end
catch
    error('input is not valid UTF-16 encoded')
end

%Binary header:
% 110110xx_xxxxxxxx 110111xx_xxxxxxxx
% 00000000 01111111 11122222 22222333
% 12345678 90123456 78901234 56789012
header_bits='110110110111';header_locs=[1:6 17:22];
multiword=UTF16([word1.' word2.']);
multiword=unique(multiword,'rows');
S2=mat2cell(multiword,ones(size(multiword,1),1),2);
unicode=UTF16;
for n=1:numel(S2)
    bin=dec2bin(double(S2{n}))';
    
    if ~strcmp(header_bits,bin(header_locs))
        error('input is not valid UTF-16 encoded')
    end
    bin(header_locs)='';
    if ~isOctave
        S3=uint32(bin2dec(bin  ));
    else
        S3=uint32(bin2dec(bin.'));%Octave needs an extra transpose.
    end
    S3=S3+65536;% 0x10000
    %Perform actual replacement.
    unicode=PatternReplace(unicode,S2{n},S3);
end
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
    unicode=UTF8;%Return input unchanged (apart from casting to uint32).
end
end
function [UTF8,flag,ME]=UTF8_to_unicode_internal(UTF8,return_on_error)

flag='success';
ME=struct('identifier','HJW:UTF8_to_unicode:notUTF8','message','Input is not UTF-8.');

persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end

if any(UTF8>255)
    flag='error';
    if return_on_error,return,end
elseif all(UTF8<128)
    return
end

for bytes=4:-1:2
    val=bin2dec([repmat('1',1,bytes) repmat('0',1,8-bytes)]);
    multibyte=UTF8>=val & UTF8<256;%Exclude the already converted chars.
    if any(multibyte)
        multibyte=find(multibyte);multibyte=multibyte(:).';
        if numel(UTF8)<(max(multibyte)+bytes-1)
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
                %Check if the byte headers match the UTF-8 standard.
                flag='error';
                if return_on_error,return,end
                continue %leave unencoded
            end
            bin(header_locs)='';
            if ~isOctave
                S3=uint32(bin2dec(bin  ));
            else
                S3=uint32(bin2dec(bin.'));%Octave needs an extra transpose.
            end
            %Perform actual replacement.
            UTF8=PatternReplace(UTF8,S2{n},S3);
        end
    end
end
end
function [opts,ME]=validate_print_to__options(opts_in,ME)
%If any input is invalid, this returns an empty array and sets ME.message.
%
%Input struct:
%options.print_to_con=true;   % or false
%options.print_to_fid=fid;    % or []
%options.print_to_obj=h_obj;  % or []
%options.print_to_fcn=struct; % or []
%
%Output struct:
%options.fid
%options.obj
%options.fcn.h
%options.fcn.data
%options.boolean.con
%options.boolean.fid
%options.boolean.obj
%options.boolean.fcn

%Set defaults.
if nargin<2,ME=struct;end
if ~isfield(opts_in,'print_to_con'),opts_in.print_to_con=[];end
if ~isfield(opts_in,'print_to_fid'),opts_in.print_to_fid=[];end
if ~isfield(opts_in,'print_to_obj'),opts_in.print_to_obj=[];end
if ~isfield(opts_in,'print_to_fcn'),opts_in.print_to_fcn=[];end
print_to_con_default=true; % Unless a valid fid, obj, or fcn is specified.

%Initalize output.
opts=struct;

%Parse the fid. We can use ftell to determine if fprintf is going to fail.
item=opts_in.print_to_fid;
if isempty(item)
    opts.boolean.fid=false;
else
    print_to_con_default=false;
    opts.boolean.fid=true;
    opts.fid=item;
    for n=1:numel(item)
        try position=ftell(item(n));catch,position=-1;end
        if item(n)~=1 && position==-1
            ME.message=['Invalid print_to_fid parameter:',char(10),...
                'should be a valid file identifier or 1.']; %#ok<CHARTEN>
            opts=[];return
        end
    end
end

%Parse the object handle. Retrieving from multiple objects at once works, but writing that output
%back to multiple objects doesn't work if Strings are dissimilar.
item=opts_in.print_to_obj;
if isempty(item)
    opts.boolean.obj=false;
else
    print_to_con_default=false;
    opts.boolean.obj=true;
    opts.obj=item;
    for n=1:numel(item)
        try
            txt=get(item(n),'String'    ); %See if this triggers an error.
            set(    item(n),'String','' ); %Test if property is writeable.
            set(    item(n),'String',txt); %Restore original content.
        catch
            ME.message=['Invalid print_to_obj parameter:',char(10),...
                'should be a handle to an object with a writeable String property.']; %#ok<CHARTEN>
            opts=[];return
        end
    end
end

%Parse the function handles.
item=opts_in.print_to_fcn;
if isempty(item)
    opts.boolean.fcn=false;
else
    print_to_con_default=false;
    try
        for n=1:numel(item)
            if ~ismember(class(item(n).h),{'function_handle','inline'}) ...
                    || numel(item(n).h)~=1
                error('trigger error')
            end
        end
    catch
        ME.message=['Invalid print_to_fcn parameter:',char(10),...
            'should be a struct with the h field containing a function handle,',char(10),...
            'anonymous function or inline function.']; %#ok<CHARTEN>
        opts=[];return
    end
end

%Parse the logical that determines if a warning will be printed to the command window.
%This is true by default, unless an fid, obj, or fcn is specified.
item=opts_in.print_to_con;
if isempty(item)
    opts.boolean.con=print_to_con_default;
else
    [passed,opts.boolean.con]=test_if_scalar_logical(item);
    if ~passed
        ME.message=['Invalid print_to_con parameter:',char(10),...
            'should be a scalar logical.']; %#ok<CHARTEN>
        opts=[];return
    end
end
end
function warning_(options,varargin)
%Print a warning to the command window, a file and/or the String property of an object.
%The lastwarn state will be set if the warning isn't thrown with warning().
%The printed call trace omits this function, but the warning() call does not.
%
%You can also provide a struct (scalar or array) with two fields: 'h' with a function handle, and
%'data' with arbitrary data passed as third input. These functions will be run with 'warning' as
%first input. The second input is a struct with identifier, message, and stack as fields. This
%function will be run with feval (meaning the function handles can be replaced with inline
%functions or anonymous functions).
%
%The intention is to allow replacement of most warning(___) call with warning_(options,___). This
%does not apply to calls that query or set the warning state.
%
%options.boolean.con: if true print warning to command window with warning()
%options.fid:         file identifier for fprintf (array input will be indexed)
%options.boolean.fid: if true print warning to file (options.fid)
%options.obj:         handle to object with String property (array input will be indexed)
%options.boolean.obj: if true print warning to object (options.obj)
%options.fcn          struct (array input will be indexed)
%options.fcn.h:       handle of function to be run
%options.fcn.data:    data passed as third input to function to be run (optional)
%options.boolean.fnc: if true the function(s) will be run
%
%syntax:
%  warning_(options,msg)
%  warning_(options,msg,A1,...,An)
%  warning_(options,id,msg)
%  warning_(options,id,msg,A1,...,An)
%  warning_(options,ME)               %rethrow error as warning
%
%examples options struct:
%  % Write to a log file:
%  opts=struct;opts.fid=fopen('log.txt','wt');
%  % Display to a status window and bypass the command window:
%  opts=struct;opts.boolean.con=false;opts.obj=uicontrol_object_handle;
%  % Write to 2 log files:
%  opts=struct;opts.fid=[fopen('log2.txt','wt') fopen('log.txt','wt')];

persistent this_fun
if isempty(this_fun),this_fun=func2str(@warning_);end

%Parse options struct.
if isempty(options),options=struct;end%allow empty input to revert to default
options=parse_warning_error_redirect_options(options);
[id,msg,stack,trace]=parse_warning_error_redirect_inputs(varargin{:});
ME=struct('identifier',id,'message',msg,'stack',stack);

if options.boolean.con
    if ~isempty(id),warning(id,'%s',msg),else,warning(msg), end
else
    if ~isempty(id),lastwarn(msg,id);    else,lastwarn(msg),end
end

if options.boolean.obj
    msg_=msg;while msg_(end)==10,msg_(end)=[];end%Crop trailing newline.
    if any(msg_==10)  % Parse to cellstr and prepend warning.
        msg_=char2cellstr(['Warning: ' msg_]);
    else              % Only prepend warning.
        msg_=['Warning: ' msg_];
    end
    set(options.obj,'String',msg_)
    for OBJ=options.obj(:).'
        try set(OBJ,'String',msg_);catch,end
    end
end

if options.boolean.fid || options.boolean.fcn
    skip_layers=2;%Remove this function and the get_trace function from the trace.
    [trace,stack]=get_trace(skip_layers);
end

if options.boolean.fid
    for FID=options.fid(:).'
        try fprintf(FID,'Warning: %s\n%s',msg,trace);catch,end
    end
end

if options.boolean.fcn
    if ismember(this_fun,{stack.name})
        %To prevent an infinite loop, trigger an error.
        error('prevent recursion')
    end
    for FCN=options.fcn(:).'
        if isfield(FCN,'data')
            try feval(FCN.h,'warning',ME,FCN.data);catch,end
        else
            try feval(FCN.h,'warning',ME);catch,end
        end
    end
end
end