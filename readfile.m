function data=readfile(filename,varargin)
%Read a UTF-8 or ANSI (US-ASCII) file
%
% Syntax:
%   data=readfile(filename)
%   data=readfile(___,options)
%   data=readfile(___,Name,Value)
%
% Input/output arguments:
% data:
%   An n-by-1 cell (1 cell per line in the file, even empty lines).
% filename:
%   A char array with either relative or absolute path, or a URL.
% options:
%   A struct with Name,Value parameters. Missing parameters are filled with the defaults listed
%   below. Using incomplete parameter names or incorrect capitalization is allowed, as long as
%   there is a unique match.
%   Parameters related to warning/error redirection will be parsed first.
%
% Name,Value parameters:
%   err_on_ANSI:
%      If set to true, an error will be thrown when the input file is not recognized as UTF-8
%      encoded. This should normally not be an issue, as ANSI files can be read as well with this
%      function. [default=false;]
%   EmptyLineRule:
%      This contains a description of how empty lines should be handled. Lines that only contain
%      whitespace are considered empty as well, to conform to the behavior of readlines (this
%      therefore also depends on the Whitespace parameter). Valid values are 'read', 'skip',
%      'error', 'skipleading', and 'skiptrailing'.
%      The latter two are not available for readlines. Values can be entered as a scalar string or
%      as a char array. [default='read';]
%   WhitespaceRule:
%      This contains a description of how should leading and trailing whitespace be handled on each
%      line. Depending on the value of the Whitespace parameter this is equivalent to readlines.
%      Valid values are 'preserve', 'trim', 'trimleading', and 'trimtrailing'.
%      [default='preserve';]
%   LineEnding:
%      This parameter determines which characters are considered line ending characters. String
%      arrays and cell arrays of char vectors are parsed by sprintf, with each element being
%      considered a line break. String scalars and character vectors are treated as literal.
%      The default is {'\n','\r','\r\n'} meaning that \n\r is considered 2 line ends. This will not
%      be checked for any overlap and will be processed sequentially. The only is the default,
%      which will be sorted to {'\r\n','\n','\r'}. [default={'\n','\r','\r\n'};]
%   Whitespace:
%      This parameter determines which characters are treated as whitespace for the purposes of
%      EmptyLineRule and WhitespaceRule. This should be a char vector or a scalar string. Cell
%      arrays of char vectors are parsed by sprintf and concatenated. Note that the default for
%      readlines is sprintf(' \b\t'), but in this function this is expanded.
%      [default=[8 9 28:32 160 5760 8192:8202 8239 8287 12288];]
%   weboptions:
%      For online files, this parameter allows using weboptions. For releases without weboptions
%      and for offline files, this parameter is ignored. Note that the content type option will be
%      overwritten. [default=weboptions;]
%   UseReadlinesDefaults:
%      Reproduce the default behavior of readlines as closely as possible. This includes
%      reproducing a bug which causes all characters that require 2 uint16 values to encode in
%      UTF-16 (everything outside the base multilingual plane, i.e. most emoji) to be converted to
%      char(26).
%      This will not convert the output to a string array. [default=false;]
%   print_to_con:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      A logical that controls whether warnings and other output will be printed to the command
%      window. Errors can't be turned off. [default=true;]
%      Specifying print_to_fid, print_to_obj, or print_to_fcn will change the default to false,
%      unless parsing of any of the other exception redirection options results in an error.
%   print_to_fid:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      The file identifier where console output will be printed. Errors and warnings will be
%      printed including the call stack. You can provide the fid for the command window (fid=1) to
%      print warnings as text. Errors will be printed to the specified file before being actually
%      thrown. [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_obj:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      The handle to an object with a String property, e.g. an edit field in a GUI where console
%      output will be printed. Messages with newline characters (ignoring trailing newlines) will
%      be returned as a cell array. This includes warnings and errors, which will be printed
%      without the call stack. Errors will be written to the object before the error is actually
%      thrown. [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_fcn:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      A struct with a function handle, anonymous function or inline function in the 'h' field and
%      optionally additional data in the 'data' field. The function should accept three inputs: a
%      char array (either 'warning' or 'error'), a struct with the message, id, and stack, and the
%      optional additional data. The function(s) will be run before the error is actually thrown.
%      [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_params:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      This struct contains the optional parameters for the error_ and warning_ functions.
%      Each field can also be specified as ['print_to_option_' parameter_name]. This can be used to
%      avoid nested struct definitions.
%      ShowTraceInMessage:
%        [default=false] Show the function trace in the message section. Unlike the normal results
%        of rethrow/warning, this will not result in clickable links.
%      WipeTraceForBuiltin:
%        [default=false] Wipe the trace so the rethrow/warning only shows the error/warning message
%        itself. Note that the wiped trace contains the calling line of code (along with the
%        function name and line number), while the generated trace does not.
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
%|  Version: 4.1.0                                                         |%
%|  Date:    2022-12-18                                                    |%
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
%   Starting from R2021a, readlines also supports reading online files.
% - Incorrect reading of files should only occur if the download to a temporary location fails.
%   (NB: this should be a rare occurence) Modern releases of Matlab (>=R2015a) are expected to read
%   every file correctly, except for ANSI files containing special characters. GNU Octave has
%   trouble with many ANSI files. Older releases of Matlab have the same results as Octave for ANSI
%   files, but also have issues with some UTF-8 files. Interestingly, R13 (v6.5) performs better on
%   ANSI files, but worse on UTF-8.
%
% /=========================================================================================\
% ||                     | Windows             | Linux               | MacOS               ||
% ||---------------------------------------------------------------------------------------||
% || Matlab R2022b       | W10: Pass           | Ubuntu 22.04: Pass  | Monterey: Pass      ||
% || Matlab R2022a       | W10: Pass           |                     |                     ||
% || Matlab R2021b       | W10: Pass           | Ubuntu 22.04: Pass  | Monterey: Pass      ||
% || Matlab R2021a       | W10: Pass           |                     |                     ||
% || Matlab R2020b       | W10: Pass           | Ubuntu 22.04: Pass  | Monterey: Pass      ||
% || Matlab R2020a       | W10: Pass           |                     |                     ||
% || Matlab R2019b       | W10: Pass           | Ubuntu 22.04: Pass  | Monterey: Pass      ||
% || Matlab R2019a       | W10: Pass           |                     |                     ||
% || Matlab R2018a       | W10: Pass           | Ubuntu 22.04: Pass  |                     ||
% || Matlab R2017b       | W10: Pass           | Ubuntu 22.04: Pass  | Monterey: Pass      ||
% || Matlab R2016b       | W10: Pass           | Ubuntu 22.04: Pass  | Monterey: Pass      ||
% || Matlab R2015a       | W10: Pass           | Ubuntu 22.04: Pass  |                     ||
% || Matlab R2013b       | W10: Pass           |                     |                     ||
% || Matlab R2012a       |                     | Ubuntu 22.04: Pass  |                     ||
% || Matlab R2011a       | W10: Pass           | Ubuntu 22.04: Pass  |                     ||
% || Matlab R2010b       |                     | Ubuntu 22.04: Pass  |                     ||
% || Matlab R2010a       | W7: Pass            |                     |                     ||
% || Matlab R2007b       | W10: Pass           |                     |                     ||
% || Matlab 7.1 (R14SP3) | XP: Pass            |                     |                     ||
% || Matlab 6.5 (R13)    | W10: Pass           |                     |                     ||
% || Octave 7.2.0        | W10: Pass           |                     |                     ||
% || Octave 6.2.0        | W10: Pass           | Raspbian 11: Pass   | Catalina: Pass      ||
% || Octave 5.2.0        | W10: Pass           |                     |                     ||
% || Octave 4.4.1        | W10: Pass           |                     | Catalina: Pass      ||
% \=========================================================================================/

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
    error('HJW:readfile:nargin','Incorrect number of input arguments.')
end
if ~(nargout==0 || nargout==1) % Might trigger 'MATLAB:TooManyOutputs' instead.
    error('HJW:readfile:nargout','Incorrect number of output arguments.')
end
[success,opts,ME] = readfile_parse_inputs(filename,varargin{:});
if ~success
    % If the parsing of print_to failed (which is tried first), the default will be used.
    error_(opts.print_to,ME)
else
    [filename,print_to,legacy,UseURLread,err_on_ANSI,EmptyLineRule,Whitespace,LineEnding,...
        FailMultiword_UTF16,WhitespaceRule,webopts] = ...
        deal(opts.filename,opts.print_to,opts.legacy,opts.UseURLread,opts.err_on_ANSI,...
        opts.EmptyLineRule,opts.Whitespace,opts.LineEnding,opts.FailMultiword_UTF16,...
        opts.WhitespaceRule,opts.weboptions);
end

if opts.OfflineFile
    data = readfile_from_file(filename,LineEnding,print_to,err_on_ANSI);
else
    if ~legacy.allows_https && strcmpi(filename(1:min(end,8)),'https://')
        warning_(print_to,'HJW:readfile:httpsNotSupported',...
            ['This implementation of urlread probably doesn''t allow https requests.',char(10),...
            'The next lines of code will probably result in an error.']) %#ok<CHARTEN>
    end
    str = readfile_from_URL(filename,UseURLread,print_to,LineEnding,err_on_ANSI,webopts);
    if isa(str,'cell') % The file was read from temporary downloaded version.
        data = str;
    else
        % This means the download failed. Some files will not work.
        invert = true;
        str = convert_from_codepage(str,invert);
        try ME = []; %#ok<NASGU>
            [ii,isUTF8,converted] = UTF8_to_unicode(str); %#ok<ASGLU>
        catch ME;if isempty(ME),ME = lasterror;end %#ok<LERR>
            if strcmp(ME.identifier,'HJW:UTF8_to_unicode:notUTF8')
                isUTF8 = false;
            else
                error_(print_to,ME)
            end
        end
        if isUTF8
            str = unicode_to_char(converted);
        end
        if isa(LineEnding,'double') && isempty(LineEnding)
            data = char2cellstr(str);
        else
            data = char2cellstr(str,LineEnding);
        end
    end
end

% Determine the location of whitespace, but only if relevant.
if ~strcmp(EmptyLineRule,'read') || ~strcmp(WhitespaceRule,'preserve')
    L = cellfun('isempty',data);
    for n=find(~L).'
        % The cellfun call will only find completely empty lines, while readlines implicitly
        % considers lines with only whitespace empty.
        tmp = ismember(data{n},Whitespace);
        L(n) = all(tmp);
        if ~strcmp(WhitespaceRule,'preserve')
            % If there is only whitespace, take a shortcut by wiping the line now.
            if L(n),data{n} = '';continue,end
            % If the first and last chars are whitespace, triming will have no effect.
            if ~tmp(1) && ~tmp(end),continue,end
            % Find the indices of non-whitespace.
            switch WhitespaceRule
                case 'trim'
                    inds = find(~tmp);inds = inds([1 end]);
                case 'trimleading'
                    % Use findND to extend the syntax for old Matlab releases.
                    inds = [findND(~tmp,1) numel(tmp)];
                case 'trimtrailing'
                    % Use findND to extend the syntax for old Matlab releases.
                    inds = [1 findND(~tmp,1,'last')];
            end
            data{n} = data{n}(inds(1):inds(2));
        end
    end
end
if ~strcmp(EmptyLineRule,'read')
    switch EmptyLineRule
        % To allow the expanded syntax for find(), the findND() function is used instead, as that
        % extends the syntax for find() on old releases of Matlab.
        case 'skip'
            data(L) = [];
        case 'error'
            if any(L)
                error_(print_to,'HJW:readfile:EmptyLinesRuleError',...
                    'Unexpected empty line detected on row %d',findND(L,1))
            end
        case 'skipleading'
            if L(1)
                ind = 1:(findND(~L,1,'first')-1);
                data(ind) = [];
            end
        case 'skiptrailing'
            if L(end)
                ind = (1+findND(~L,1,'last')):numel(L);
                data(ind) = [];
            end
    end
end
persistent isOctave,if isempty(isOctave),isOctave = ifversion('<',0,'Octave','>',0);end
if FailMultiword_UTF16
    % The readlines function fails for multiword UTF16 characters, rendering them as char(26). To
    % keep complete equivalence, that behavior is replicated here.
    % The bit-pattern is 110110xx_xxxxxxxx 110111xx_xxxxxxxx, so we can simply detect any value
    % between 55296 and 56319. For Octave we can check if there are 4-byte characters.
    for n=1:numel(data)
        if isOctave
            if any(data{n}>=240)
                % Now we need to properly convert to UTF-32, replace by 26 and convert back.
                data{n} = replace_multiword_UTF16_by_26(data{n});
            end
        else
            if any(data{n}>=55296 & data{n}<=56319)
                % Now we need to properly convert to UTF-32, replace by 26 and convert back.
                data{n} = replace_multiword_UTF16_by_26(data{n});
            end
        end
    end
end
end
function out=replace_multiword_UTF16_by_26(in)
%Replace all multiword UTF-16 (i.e. U+10000 to U+10FFFF) with char(26)
persistent isOctave,if isempty(isOctave),isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;end
if isOctave
    unicode = UTF8_to_unicode(in);
else
    unicode = UTF16_to_unicode(in);
end
% Perform replacement.
unicode(unicode>=65536) = 26;
% Convert back to proper encoding
if isOctave
    out = char(unicode_to_UTF8(unicode));
else
    out = char(unicode_to_UTF16(unicode));
end
end
function out=bsxfun_plus(in1,in2)
%Implicit expansion for plus(), but without any input validation.
persistent type
if isempty(type)
    type = ...
        double(hasFeature('ImplicitExpansion')) + ...
        double(hasFeature('bsxfun'));
end
if type==2
    % Implicit expansion is available.
    out = in1+in2;
elseif type==1
    % Implicit expansion is only available with bsxfun.
    out = bsxfun(@plus,in1,in2);
else
    % No implicit expansion, expand explicitly.
    sz1 = size(in1);
    sz2 = size(in2);
    if min([sz1 sz2])==0
        % Construct an empty array of the correct size.
        sz1(sz1==0) = inf;sz2(sz2==0) = inf;
        sz = max(sz1,sz2);
        sz(isinf(sz)) = 0;
        % Create an array and cast it to the correct type.
        out = feval(str2func(class(in1)),zeros(sz));
        return
    end
    in1 = repmat(in1,max(1,sz2./sz1));
    in2 = repmat(in2,max(1,sz1./sz2));
    out = in1+in2;
end
end
function c=char2cellstr(str,LineEnding)
% Split char or uint32 vector to cell (1 cell element per line). Default splits are for CRLF/CR/LF.
% The input data type is preserved.
%
% Since the largest valid Unicode codepoint is 0x10FFFF (i.e. 21 bits), all values will fit in an
% int32 as well. This is used internally to deal with different newline conventions.
%
% The second input is a cellstr containing patterns that will be considered as newline encodings.
% This will not be checked for any overlap and will be processed sequentially.

returnChar = isa(str,'char');
str = int32(str); % Convert to signed, this should not crop any valid Unicode codepoints.

if nargin<2
    % Replace CRLF, CR, and LF with -10 (in that order). That makes sure that all valid encodings
    % of newlines are replaced with the same value. This should even handle most cases of files
    % that mix the different styles, even though such mixing should never occur in a properly
    % encoded file. This considers LFCR as two line endings.
    if any(str==13)
        str = PatternReplace(str,int32([13 10]),int32(-10));
        str(str==13) = -10;
    end
    str(str==10) = -10;
else
    for n=1:numel(LineEnding)
        str = PatternReplace(str,int32(LineEnding{n}),int32(-10));
    end
end

% Split over newlines.
newlineidx = [0 find(str==-10) numel(str)+1];
c=cell(numel(newlineidx)-1,1);
for n=1:numel(c)
    s1 = (newlineidx(n  )+1);
    s2 = (newlineidx(n+1)-1);
    c{n} = str(s1:s2);
end

% Return to the original data type.
if returnChar
    for n=1:numel(c),c{n} =   char(c{n});end
else
    for n=1:numel(c),c{n} = uint32(c{n});end
end
end
function tf=CharIsUTF8
% This provides a single place to determine if the runtime uses UTF-8 or UTF-16 to encode chars.
% The advantage is that there is only 1 function that needs to change if and when Octave switches
% to UTF-16. This is unlikely, but not impossible.
persistent persistent_tf
if isempty(persistent_tf)
    if ifversion('<',0,'Octave','>',0)
        % Test if Octave has switched to UTF-16 by looking if the Euro symbol is losslessly encoded
        % with char.
        % Because we will immediately reset it, setting the state for all warnings to off is fine.
        w = struct('w',warning('off','all'));[w.msg,w.ID] = lastwarn;
        persistent_tf = ~isequal(8364,double(char(8364)));
        warning(w.w);lastwarn(w.msg,w.ID); % Reset warning state.
    else
        persistent_tf = false;
    end
end
tf = persistent_tf;
end
function str=convert_from_codepage(str,inverted)
% Convert from the Windows-1252 codepage.
persistent or ta
if isempty(or)
    % This list is complete for all characters (up to 0xFFFF) that can be encoded with ANSI.
    CPwin2UTF8 = [338 140;339 156;352 138;353 154;376 159;381 142;382 158;402 131;710 136;732 152;
        8211 150;8212 151;8216 145;8217 146;8218 130;8220 147;8221 148;8222 132;8224 134;8225 135;
        8226 149;8230 133;8240 137;8249 139;8250 155;8364 128;8482 153];
    or = CPwin2UTF8(:,2);ta = CPwin2UTF8(:,1);
end
if nargin>1 && inverted
    origin = ta;target = or;
else
    origin = or;target = ta;
end
str = uint32(str);
for m=1:numel(origin)
    str = PatternReplace(str,origin(m),target(m));
end
end
function error_(options,varargin)
%Print an error to the command window, a file and/or the String property of an object.
% The error will first be written to the file and object before being actually thrown.
%
% Apart from controlling the way an error is written, you can also run a specific function. The
% 'fcn' field of the options must be a struct (scalar or array) with two fields: 'h' with a
% function handle, and 'data' with arbitrary data passed as third input. These functions will be
% run with 'error' as first input. The second input is a struct with identifier, message, and stack
% as fields. This function will be run with feval (meaning the function handles can be replaced
% with inline functions or anonymous functions).
%
% The intention is to allow replacement of every error(___) call with error_(options,___).
%
% NB: the function trace that is written to a file or object may differ from the trace displayed by
% calling the builtin error/warning functions (especially when evaluating code sections). The
% calling code will not be included in the constructed trace.
%
% There are two ways to specify the input options. The shorthand struct described below can be used
% for fast repeated calls, while the input described below allows an input that is easier to read.
% Shorthand struct:
%  options.boolean.IsValidated: if true, validation is skipped
%  options.params:              optional parameters for error_ and warning_, as explained below
%  options.boolean.con:         only relevant for warning_, ignored
%  options.fid:                 file identifier for fprintf (array input will be indexed)
%  options.boolean.fid:         if true print error to file
%  options.obj:                 handle to object with String property (array input will be indexed)
%  options.boolean.obj:         if true print error to object (options.obj)
%  options.fcn                  struct (array input will be indexed)
%  options.fcn.h:               handle of function to be run
%  options.fcn.data:            data passed as third input to function to be run (optional)
%  options.boolean.fnc:         if true the function(s) will be run
%
% Full input description:
%   print_to_con:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      A logical that controls whether warnings and other output will be printed to the command
%      window. Errors can't be turned off. [default=true;]
%      Specifying print_to_fid, print_to_obj, or print_to_fcn will change the default to false,
%      unless parsing of any of the other exception redirection options results in an error.
%   print_to_fid:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      The file identifier where console output will be printed. Errors and warnings will be
%      printed including the call stack. You can provide the fid for the command window (fid=1) to
%      print warnings as text. Errors will be printed to the specified file before being actually
%      thrown. [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_obj:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      The handle to an object with a String property, e.g. an edit field in a GUI where console
%      output will be printed. Messages with newline characters (ignoring trailing newlines) will
%      be returned as a cell array. This includes warnings and errors, which will be printed
%      without the call stack. Errors will be written to the object before the error is actually
%      thrown. [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_fcn:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      A struct with a function handle, anonymous function or inline function in the 'h' field and
%      optionally additional data in the 'data' field. The function should accept three inputs: a
%      char array (either 'warning' or 'error'), a struct with the message, id, and stack, and the
%      optional additional data. The function(s) will be run before the error is actually thrown.
%      [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_params:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      This struct contains the optional parameters for the error_ and warning_ functions.
%      Each field can also be specified as ['print_to_option_' parameter_name]. This can be used to
%      avoid nested struct definitions.
%      ShowTraceInMessage:
%        [default=false] Show the function trace in the message section. Unlike the normal results
%        of rethrow/warning, this will not result in clickable links.
%      WipeTraceForBuiltin:
%        [default=false] Wipe the trace so the rethrow/warning only shows the error/warning message
%        itself. Note that the wiped trace contains the calling line of code (along with the
%        function name and line number), while the generated trace does not.
%
% Syntax:
%   error_(options,msg)
%   error_(options,msg,A1,...,An)
%   error_(options,id,msg)
%   error_(options,id,msg,A1,...,An)
%   error_(options,ME)               %equivalent to rethrow(ME)
%
% Examples options struct:
%   % Write to a log file:
%   opts = struct;opts.fid = fopen('log.txt','wt');
%   % Display to a status window and bypass the command window:
%   opts = struct;opts.boolean.con = false;opts.obj = uicontrol_object_handle;
%   % Write to 2 log files:
%   opts = struct;opts.fid = [fopen('log2.txt','wt') fopen('log.txt','wt')];

persistent this_fun
if isempty(this_fun),this_fun = func2str(@error_);end

% Parse options struct, allowing an empty input to revert to default.
if isempty(options),options = struct;end
options                    = parse_warning_error_redirect_options(  options  );
[id,msg,stack,trace,no_op] = parse_warning_error_redirect_inputs( varargin{:});
if no_op,return,end
if options.params.ShowTraceInMessage
    msg = sprintf('%s\n%s',msg,trace);
end
ME = struct('identifier',id,'message',msg,'stack',stack);
if options.params.WipeTraceForBuiltin
    ME.stack = stack('name','','file','','line',[]);
end

% Print to object.
if options.boolean.obj
    msg_ = msg;while msg_(end)==10,msg_(end) = '';end % Crop trailing newline.
    if any(msg_==10)  % Parse to cellstr and prepend 'Error: '.
        msg_ = char2cellstr(['Error: ' msg_]);
    else              % Only prepend 'Error: '.
        msg_ = ['Error: ' msg_];
    end
    for OBJ=options.obj(:).'
        try set(OBJ,'String',msg_);catch,end
    end
end

% Print to file.
if options.boolean.fid
    T = datestr(now,31); %#ok<DATST,TNOW1> Print the time of the error to the log as well.
    for FID=options.fid(:).'
        try fprintf(FID,'[%s] Error: %s\n%s',T,msg,trace);catch,end
    end
end

% Run function.
if options.boolean.fcn
    if ismember(this_fun,{stack.name})
        % To prevent an infinite loop, trigger an error.
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

% Actually throw the error.
rethrow(ME)
end
function [valid,filename]=filename_is_valid(filename)
% Check if the file name and path are valid (non-empty char or scalar string).
valid=true;
persistent forbidden_names
if isempty(forbidden_names)
    forbidden_names = {'CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7',...
        'COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'};
end
if isa(filename,'string') && numel(filename)==1
    % Convert a scalar string to a char array.
    filename = char(filename);
end
if ~isa(filename,'char') || numel(filename)==0
    valid = false;return
else
    % File name is indeed a char. Do a check if there are characters that can't exist in a normal
    % file name. The method used here is not fool-proof, but should cover most use cases and
    % operating systems.
    [fullpath,fn,ext] = fileparts(filename); %#ok<ASGLU> 
    fn = [fn,ext];
    if      any(ismember([char(0:31) '<>:"/\|?*'],fn)) || ...
            any(ismember(forbidden_names,upper(fn))) || ... % (ismember is case sensitive)
            any(fn(end)=='. ')
        valid = false;return
    end
end
end
function varargout=findND(X,varargin)
% Find non-zero elements in ND-arrays. Replicates all behavior from find.
%
% The syntax is equivalent to the built-in find, but extended to multi-dimensional input.
%
% The syntax with more than one input is present in the doc for R14 (Matlab 7.0), so R13 (Matlab
% 6.5) is the latest release without support for this syntax.
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
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%|                                                                         |%
%|  Version: 2.0.0                                                         |%
%|  Date:    2022-11-29                                                    |%
%|  Author:  H.J. Wisselink                                                |%
%|  Licence: CC by-nc-sa 4.0 ( creativecommons.org/licenses/by-nc-sa/4.0 ) |%
%|  Email = 'h_j_wisselink*alumnus_utwente_nl';                            |%
%|  Real_email = regexprep(Email,{'*','_'},{'@','.'})                      |%
%|                                                                         |%
%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%/%
%
% Tested on several versions of Matlab (ML 6.5 and onward) and Octave (4.4.1 and onward), and on
% multiple operating systems (Windows/Ubuntu/MacOS). You can see the full test matrix below.
% Compatibility considerations:
% - This is expected to work on all releases.

% Parse inputs.
if ~(isnumeric(X) || islogical(X)) || numel(X)==0
    error('HJW:findND:FirstInput',...
        'Expected first input (X) to be a non-empty numeric or logical array.')
end
switch nargin
    case 1 %[...] = findND(X);
        side = 'first';
        K = inf;
    case 2 %[...] = findND(X,K);
        side = 'first';
        K = varargin{1};
        if ~(isnumeric(K) || islogical(K)) || numel(K)~=1 || any(K<0)
            error('HJW:findND:SecondInput',...
                'Expected second input (K) to be a positive numeric or logical scalar.')
        end
    case 3 %[...] = FIND(X,K,'first');
        K = varargin{1};
        if ~(isnumeric(K) || islogical(K)) || numel(K)~=1 || any(K<0)
            error('HJW:findND:SecondInput',...
                'Expected second input (K) to be a positive numeric or logical scalar.')
        end
        side = varargin{2};
        if isa(side,'string') && numel(side)==1,side = char(side);end
        if ~isa(side,'char') || ~( strcmpi(side,'first') || strcmpi(side,'last'))
            error('HJW:findND:ThirdInput','Third input must be either ''first'' or ''last''.')
        end
        side = lower(side);
    otherwise
        error('HJW:findND:InputNumber','Incorrect number of inputs.')
end

% Parse outputs.
% Allowed outputs: 0, 1, nDims, nDims+1
if nargout>1 && nargout<ndims(X)
    error('HJW:findND:Output','Incorrect number of output arguments.')
end

persistent OldSyntax,if isempty(OldSyntax),OldSyntax = ifversion('<',7,'Octave','<',3);end

% Replicate the behavior of find by rounding nargout to 1 if it is 0.
varargout = cell(max(1,nargout),1);
if OldSyntax
    % The find(X,k,side) syntax was introduced in v7.
    if nargout>ndims(X)
        [ind,ignore,val] = find(X(:)); %#ok<ASGLU> (no tilde pre-R2009b)
        % X(:) converts X to a column vector. Treating X(:) as a matrix forces val to be the actual
        % value, instead of the column index.
        if length(ind)>K
            if strcmp(side,'first') % Select first K outputs.
                ind = ind(1:K);
                val = val(1:K);
            else                    % Select last K outputs.
                ind = ind((end-K+1):end);
                val = val((end-K+1):end);
            end
        end
        [varargout{1:(end-1)}] = ind2sub(size(X),ind);
        varargout{end} = val;
    else
        ind = find(X);
        if numel(ind)>K
            if strcmp(side,'first')
                % Select first K outputs.
                ind = ind(1:K);
            else
                % Select last K outputs.
                ind = ind((end-K+1):end);
            end
        end
        [varargout{:}] = ind2sub(size(X),ind);
    end
else
    if nargout>ndims(X)
        [ind,ignore,val] = find(X(:),K,side);%#ok<ASGLU>
        % X(:) converts X to a column vector. Treating X(:) as a matrix forces val to be the actual
        % value, instead of the column index.
        [varargout{1:(end-1)}] = ind2sub(size(X),ind);
        varargout{end} = val;
    else
        ind = find(X,K,side);
        [varargout{:}] = ind2sub(size(X),ind);
    end
end
end
function [str,stack]=get_trace(skip_layers,stack)
if nargin==0,skip_layers = 1;end
if nargin<2, stack = dbstack;end
stack(1:skip_layers) = [];

% Parse the ML6.5 style of dbstack (the name field includes full file location).
if ~isfield(stack,'file')
    for n=1:numel(stack)
        tmp = stack(n).name;
        if strcmp(tmp(end),')')
            % Internal function.
            ind = strfind(tmp,'(');
            name = tmp( (ind(end)+1):(end-1) );
            file = tmp(1:(ind(end)-2));
        else
            file = tmp;
            [ignore,name] = fileparts(tmp); %#ok<ASGLU>
        end
        [ignore,stack(n).file] = fileparts(file); %#ok<ASGLU>
        stack(n).name = name;
    end
end

% Parse Octave style of dbstack (the file field includes full file location).
persistent isOctave,if isempty(isOctave),isOctave=ifversion('<',0,'Octave','>',0);end
if isOctave
    for n=1:numel(stack)
        [ignore,stack(n).file] = fileparts(stack(n).file); %#ok<ASGLU>
    end
end

% Create the char array with a (potentially) modified stack.
s = stack;
c1 = '>';
str = cell(1,numel(s)-1);
for n=1:numel(s)
    [ignore_path,s(n).file,ignore_ext] = fileparts(s(n).file); %#ok<ASGLU>
    if n==numel(s),s(n).file = '';end
    if strcmp(s(n).file,s(n).name),s(n).file = '';end
    if ~isempty(s(n).file),s(n).file = [s(n).file '>'];end
    str{n} = sprintf('%c In %s%s (line %d)\n',c1,s(n).file,s(n).name,s(n).line);
    c1 = ' ';
end
str = horzcat(str{:});
end
function tf=hasFeature(feature)
% Provide a single point to encode whether specific features are available.
persistent FeatureList
if isempty(FeatureList)
    FeatureList = struct(...
        'ImplicitExpansion',ifversion('>=','R2016b','Octave','>' ,0),...
        'bsxfun'           ,ifversion('>=','R2007a','Octave','>' ,0),...
        'IntegerArithmetic',ifversion('>=','R2010b','Octave','>' ,0),...
        'String'           ,ifversion('>=','R2016b','Octave','<' ,0),...
        'HTTPS_support'    ,ifversion('>' ,0       ,'Octave','<' ,0),...
        'json'             ,ifversion('>=','R2016b','Octave','>=',7),...
        'strtrim'          ,ifversion('>=',7       ,'Octave','>=',0),...
        'accumarray'       ,ifversion('>=',7       ,'Octave','>=',0));
    FeatureList.CharIsUTF8 = CharIsUTF8;
end
tf = FeatureList.(feature);
end
function tf=ifversion(test,Rxxxxab,Oct_flag,Oct_test,Oct_ver)
%Determine if the current version satisfies a version restriction
%
% To keep the function fast, no input checking is done. This function returns a NaN if a release
% name is used that is not in the dictionary.
%
% Syntax:
%   tf = ifversion(test,Rxxxxab)
%   tf = ifversion(test,Rxxxxab,'Octave',test_for_Octave,v_Octave)
%
% Input/output arguments:
% tf:
%   If the current version satisfies the test this returns true. This works similar to verLessThan.
% Rxxxxab:
%   A char array containing a release description (e.g. 'R13', 'R14SP2' or 'R2019a') or the numeric
%   version (e.g. 6.5, 7, or 9.6).
% test:
%   A char array containing a logical test. The interpretation of this is equivalent to
%   eval([current test Rxxxxab]). For examples, see below.
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
%|  Version: 1.1.2                                                         |%
%|  Date:    2022-09-16                                                    |%
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

% The decimal of the version numbers are padded with a 0 to make sure v7.10 is larger than v7.9.
% This does mean that any numeric version input needs to be adapted. multiply by 100 and round to
% remove the potential for float rounding errors.
% Store in persistent for fast recall (don't use getpref, as that is slower than generating the
% variables and makes updating this function harder).
persistent  v_num v_dict octave
if isempty(v_num)
    % Test if Octave is used instead of Matlab.
    octave = exist('OCTAVE_VERSION', 'builtin');
    
    % Get current version number. This code was suggested by Jan on this thread:
    % https://mathworks.com/matlabcentral/answers/1671199#comment_2040389
    v_num = [100, 1] * sscanf(version, '%d.%d', 2);
    
    % Get dictionary to use for ismember.
    v_dict = {...
        'R13' 605;'R13SP1' 605;'R13SP2' 605;'R14' 700;'R14SP1' 700;'R14SP2' 700;
        'R14SP3' 701;'R2006a' 702;'R2006b' 703;'R2007a' 704;'R2007b' 705;
        'R2008a' 706;'R2008b' 707;'R2009a' 708;'R2009b' 709;'R2010a' 710;
        'R2010b' 711;'R2011a' 712;'R2011b' 713;'R2012a' 714;'R2012b' 800;
        'R2013a' 801;'R2013b' 802;'R2014a' 803;'R2014b' 804;'R2015a' 805;
        'R2015b' 806;'R2016a' 900;'R2016b' 901;'R2017a' 902;'R2017b' 903;
        'R2018a' 904;'R2018b' 905;'R2019a' 906;'R2019b' 907;'R2020a' 908;
        'R2020b' 909;'R2021a' 910;'R2021b' 911;'R2022a' 912;'R2022b' 913};
end

if octave
    if nargin==2
        warning('HJW:ifversion:NoOctaveTest',...
            ['No version test for Octave was provided.',char(10),...
            'This function might return an unexpected outcome.']) %#ok<CHARTEN>
        if isnumeric(Rxxxxab)
            v = 0.1*Rxxxxab+0.9*fix(Rxxxxab);v = round(100*v);
        else
            L = ismember(v_dict(:,1),Rxxxxab);
            if sum(L)~=1
                warning('HJW:ifversion:NotInDict',...
                    'The requested version is not in the hard-coded list.')
                tf = NaN;return
            else
                v = v_dict{L,2};
            end
        end
    elseif nargin==4
        % Undocumented shorthand syntax: skip the 'Octave' argument.
        [test,v] = deal(Oct_flag,Oct_test);
        % Convert 4.1 to 401.
        v = 0.1*v+0.9*fix(v);v = round(100*v);
    else
        [test,v] = deal(Oct_test,Oct_ver);
        % Convert 4.1 to 401.
        v = 0.1*v+0.9*fix(v);v = round(100*v);
    end
else
    % Convert R notation to numeric and convert 9.1 to 901.
    if isnumeric(Rxxxxab)
        v = 0.1*Rxxxxab+0.9*fix(Rxxxxab);v = round(100*v);
    else
        L = ismember(v_dict(:,1),Rxxxxab);
        if sum(L)~=1
            warning('HJW:ifversion:NotInDict',...
                'The requested version is not in the hard-coded list.')
            tf = NaN;return
        else
            v = v_dict{L,2};
        end
    end
end
switch test
    case '==', tf = v_num == v;
    case '<' , tf = v_num <  v;
    case '<=', tf = v_num <= v;
    case '>' , tf = v_num >  v;
    case '>=', tf = v_num >= v;
end
end
function [opts,replaced]=parse_NameValue(default,varargin)
%Match the Name,Value pairs to the default option, attempting to autocomplete
%
% The autocomplete ignores incomplete names, case, underscores, and dashes, as long as a unique
% match can be found.
%
% The first output is a struct with the same fields as the first input, with field contents
% replaced according to the supplied options struct or Name,Value pairs.
% The second output is a cellstr containing the field names that have been set.
%
% If this fails to find a match, this will throw an error with the offending name as the message.
%
% If there are multiple occurences of a Name, only the last Value will be returned. This is the
% same as Matlab internal functions like plot. GNU Octave also has this behavior.
%
% If a struct array is provided, only the first element will be used. An empty struct array will
% trigger an error.

switch numel(default)
    case 0
        error('parse_NameValue:MixedOrBadSyntax',...
            'Optional inputs must be entered as Name,Value pairs or as a scalar struct.')
    case 1
        % Do nothing.
    otherwise
        % If this is a struct array, explicitly select the first element.
        default=default(1);
end

% Create default output and return if no other inputs exist.
opts = default;replaced = {};
if nargin==1,return,end

% Unwind an input struct to Name,Value pairs.
try
    struct_input = numel(varargin)==1 && isa(varargin{1},'struct');
    NameValue_input = mod(numel(varargin),2)==0 && all(...
        cellfun('isclass',varargin(1:2:end),'char'  ) | ...
        cellfun('isclass',varargin(1:2:end),'string')   );
    if ~( struct_input || NameValue_input )
        error('trigger')
    end
    if nargin==2
        Names = fieldnames(varargin{1});
        Values = struct2cell(varargin{1});
    else
        % Wrap in cellstr to account for strings (this also deals with the fun(Name=Value) syntax).
        Names = cellstr(varargin(1:2:end));
        Values = varargin(2:2:end);
    end
    if ~iscellstr(Names),error('trigger');end %#ok<ISCLSTR>
catch
    % If this block errors, that is either because a missing Value with the Name,Value syntax, or
    % because the struct input is not a struct, or because an attempt was made to mix the two
    % styles. In future versions of this functions an effort might be made to handle such cases.
    error('parse_NameValue:MixedOrBadSyntax',...
        'Optional inputs must be entered as Name,Value pairs or as a scalar struct.')
end

% The fieldnames will be converted to char matrices in the section below. First an exact match is
% tried, then a case-sensitive (partial) match, then ignoring case, followed by ignoring any
% underscores, and lastly ignoring dashes.
default_Names = fieldnames(default);
Names_char    = cell(1,4);
Names_cell{1} = default_Names;
Names_cell{2} = lower(Names_cell{1});
Names_cell{3} = strrep(Names_cell{2},'_','');
Names_cell{4} = strrep(Names_cell{3},'-','');

% Allow spaces by replacing them with underscores.
Names = strrep(Names,' ','_');

% Attempt to match the names.
replaced = false(size(default_Names));
for n=1:numel(Names)
    name = Names{n};
    
    % Try a case-sensitive match.
    [match_idx,Names_char{1}] = parse_NameValue__find_match(Names_char{1},Names_cell{1},name);
    
    % Try a case-insensitive match.
    if numel(match_idx)~=1
        name = lower(name);
        [match_idx,Names_char{2}] = parse_NameValue__find_match(Names_char{2},Names_cell{2},name);
    end
    
    % Try a case-insensitive match ignoring underscores.
    if numel(match_idx)~=1
        name = strrep(name,'_','');
        [match_idx,Names_char{3}] = parse_NameValue__find_match(Names_char{3},Names_cell{3},name);
    end
    
    % Try a case-insensitive match ignoring underscores and dashes.
    if numel(match_idx)~=1
        name = strrep(name,'-','');
        [match_idx,Names_char{4}] = parse_NameValue__find_match(Names_char{4},Names_cell{4},name);
    end
    
    if numel(match_idx)~=1
        error('parse_NameValue:NonUniqueMatch',Names{n})
    end
    
    % Store the Value in the output struct and mark it as replaced.
    opts.(default_Names{match_idx}) = Values{n};
    replaced(match_idx)=true;
end
replaced = default_Names(replaced);
end
function [match_idx,Names_char]=parse_NameValue__find_match(Names_char,Names_cell,name)
% Try to match the input field to the fields of the struct.

% First attempt an exact match.
match_idx = find(ismember(Names_cell,name));
if numel(match_idx)==1,return,end

% Only spend time building the char array if this point is reached.
if isempty(Names_char),Names_char = parse_NameValue__name2char(Names_cell);end

% Since the exact match did not return a unique match, attempt to match the start of each array.
% Select the first part of the array. Since Names is provided by the user it might be too long.
tmp = Names_char(:,1:min(end,numel(name)));
if size(tmp,2)<numel(name)
    tmp = [tmp repmat(' ', size(tmp,1) , numel(name)-size(tmp,2) )];
end

% Find the number of non-matching characters on every row. The cumprod on the logical array is
% to make sure that only the starting match is considered.
non_matching = numel(name)-sum(cumprod(double(tmp==repmat(name,size(tmp,1),1)),2),2);
match_idx = find(non_matching==0);
end
function Names_char=parse_NameValue__name2char(Names_char)
% Convert a cellstr to a padded char matrix.
len = cellfun('prodofsize',Names_char);maxlen = max(len);
for n=find(len<maxlen).' % Pad with spaces where needed
    Names_char{n}((end+1):maxlen) = ' ';
end
Names_char = vertcat(Names_char{:});
end
function [opts,named_fields]=parse_print_to___get_default
% This returns the default struct for use with warning_ and error_. The second output contains all
% the possible field names that can be used with the parser.
persistent opts_ named_fields_
if isempty(opts_)
    [opts_,named_fields_] = parse_print_to___get_default_helper;
end
opts = opts_;
named_fields = named_fields_;
end
function [opts_,named_fields_]=parse_print_to___get_default_helper
default_params = struct(...
    'ShowTraceInMessage',false,...
    'WipeTraceForBuiltin',false);
opts_ = struct(...
    'params',default_params,...
    'fid',[],...
    'obj',[],...
    'fcn',struct('h',{},'data',{}),...
    'boolean',struct('con',[],'fid',false,'obj',false,'fcn',false,'IsValidated',false));
named_fields_params = fieldnames(default_params);
for n=1:numel(named_fields_params)
    named_fields_params{n} = ['option_' named_fields_params{n}];
end
named_fields_ = [...
    named_fields_params;...
    {'con';'fid';'obj';'fcn'}];
for n=1:numel(named_fields_)
    named_fields_{n} = ['print_to_' named_fields_{n}];
end
named_fields_ = sort(named_fields_);
end
function opts=parse_print_to___named_fields_to_struct(named_struct)
% This function parses the named fields (print_to_con, print_to_fcn, etc) to the option struct
% syntax that warning_ and error_ expect. Any additional fields are ignored.
% Note that this function will not validate the contents after parsing and the validation flag will
% be set to false.
%
% Input struct:
% options.print_to_con=true;      % or false
% options.print_to_fid=fid;       % or []
% options.print_to_obj=h_obj;     % or []
% options.print_to_fcn=struct;    % or []
% options.print_to_params=struct; % or []
%
% Output struct:
% options.params
% options.fid
% options.obj
% options.fcn.h
% options.fcn.data
% options.boolean.con
% options.boolean.fid
% options.boolean.obj
% options.boolean.fcn
% options.boolean.IsValidated

persistent default print_to_option__field_names_in print_to_option__field_names_out
if isempty(print_to_option__field_names_in)
    % Generate the list of options that can be set by name.
    [default,print_to_option__field_names_in] = parse_print_to___get_default;
    pattern = 'print_to_option_';
    for n=numel(print_to_option__field_names_in):-1:1
        if ~strcmp(pattern,print_to_option__field_names_in{n}(1:min(end,numel(pattern))))
            print_to_option__field_names_in( n)=[];
        end
    end
    print_to_option__field_names_out = strrep(print_to_option__field_names_in,pattern,'');
end

opts = default;

if isfield(named_struct,'print_to_params')
    opts.params = named_struct.print_to_params;
else
    % There might be param fields set with ['print_to_option_' parameter_name].
    for n=1:numel(print_to_option__field_names_in)
        field_in = print_to_option__field_names_in{n};
        if isfield(named_struct,print_to_option__field_names_in{n})
            field_out = print_to_option__field_names_out{n};
            opts.params.(field_out) = named_struct.(field_in);
        end
    end
end

if isfield(named_struct,'print_to_fid'),opts.fid = named_struct.print_to_fid;end
if isfield(named_struct,'print_to_obj'),opts.obj = named_struct.print_to_obj;end
if isfield(named_struct,'print_to_fcn'),opts.fcn = named_struct.print_to_fcn;end
if isfield(named_struct,'print_to_con'),opts.boolean.con = named_struct.print_to_con;end
opts.boolean.IsValidated = false;
end
function [isValid,ME,opts]=parse_print_to___validate_struct(opts)
% This function will validate all interactions. If a third output is requested, any invalid targets
% will be removed from the struct so the remaining may still be used.
% Any failures will result in setting options.boolean.con to true.
%
% NB: Validation will be skipped if opts.boolean.IsValidated is set to true.

% Initialize some variables.
AllowFailed = nargout>=3;
ME=struct('identifier','','message','');
isValid = true;
if nargout>=3,AllowFailed = true;end

% Check to see whether the struct has already been verified.
[passed,IsValidated] = test_if_scalar_logical(opts.boolean.IsValidated);
if passed && IsValidated
    return
end

% Parse the logical that determines if a warning will be printed to the command window.
% This is true by default, unless an fid, obj, or fcn is specified, which is ensured elsewhere. If
% the fid/obj/fcn turn out to be invalid, this will revert to true at the end of this function.
[passed,opts.boolean.con] = test_if_scalar_logical(opts.boolean.con);
if ~passed && ~isempty(opts.boolean.con)
    ME.message = ['Invalid print_to_con parameter:',char(10),...
        'should be a scalar logical or empty double.']; %#ok<CHARTEN>
    ME.identifier = 'HJW:print_to:ValidationFailed';
    isValid = false;
    if ~AllowFailed,return,end
end

[ErrorFlag,opts.fid] = validate_fid(opts.fid);
if ErrorFlag
    ME.message = ['Invalid print_to_fid parameter:',char(10),...
        'should be a valid file identifier or 1.']; %#ok<CHARTEN>
    ME.identifier = 'HJW:print_to:ValidationFailed';
    isValid = false;
    if ~AllowFailed,return,end
end
opts.boolean.fid = ~isempty(opts.fid);

[ErrorFlag,opts.obj]=validate_obj(opts.obj);
if ErrorFlag
    ME.message = ['Invalid print_to_obj parameter:',char(10),...
        'should be a handle to an object with a writeable String property.']; %#ok<CHARTEN>
    ME.identifier = 'HJW:print_to:ValidationFailed';
    isValid = false;
    if ~AllowFailed,return,end
end
opts.boolean.obj = ~isempty(opts.obj);

[ErrorFlag,opts.fcn]=validate_fcn(opts.fcn);
if ErrorFlag
    ME.message = ['Invalid print_to_fcn parameter:',char(10),...
        'should be a struct with the h field containing a function handle,',char(10),...
        'anonymous function or inline function.']; %#ok<CHARTEN>
    ME.identifier = 'HJW:print_to:ValidationFailed';
    isValid = false;
    if ~AllowFailed,return,end
end
opts.boolean.fcn = ~isempty(opts.fcn);

[ErrorFlag,opts.params]=validate_params(opts.params);
if ErrorFlag
        ME.message = ['Invalid print_to____params parameter:',char(10),...
            'should be a scalar struct uniquely matching parameter names.']; %#ok<CHARTEN>
        ME.identifier = 'HJW:print_to:ValidationFailed';
    isValid = false;
    if ~AllowFailed,return,end
end

if isempty(opts.boolean.con)
    % Set default value.
    opts.boolean.con = ~any([opts.boolean.fid opts.boolean.obj opts.boolean.fcn]);
end

if ~isValid
    % If any error is found, enable the print to the command window to ensure output to the user.
    opts.boolean.con = true;
end

% While not all parameters may be present from the input struct, the resulting struct is as much
% validated as is possible to test automatically.
opts.boolean.IsValidated = true;
end
function [ErrorFlag,item]=validate_fid(item)
% Parse the fid. We can use ftell to determine if fprintf is going to fail.
ErrorFlag = false;
for n=numel(item):-1:1
    try position = ftell(item(n));catch,position = -1;end
    if item(n)~=1 && position==-1
        ErrorFlag = true;
        item(n)=[];
    end
end
end
function [ErrorFlag,item]=validate_obj(item)
% Parse the object handle. Retrieving from multiple objects at once works, but writing that output
% back to multiple objects doesn't work if Strings are dissimilar.
ErrorFlag = false;
for n=numel(item):-1:1
    try
        txt = get(item(n),'String'    ); % See if this triggers an error.
        set(      item(n),'String','' ); % Test if property is writable.
        set(      item(n),'String',txt); % Restore original content.
    catch
        ErrorFlag = true;
        item(n)=[];
    end
end
end
function [ErrorFlag,item]=validate_fcn(item)
% Parse the function handles. There is no convenient way to test whether the function actually
% accepts the inputs.
ErrorFlag = false;
for n=numel(item):-1:1
    if ~ismember(class(item(n).h),{'function_handle','inline'}) || numel(item(n).h)~=1
        ErrorFlag = true;
        item(n)=[];
    end
end
end
function [ErrorFlag,item]=validate_params(item)
% Fill any missing options with defaults. If the input is not a struct, this will return the
% defaults. Any fields that cause errors during parsing are ignored.
ErrorFlag = false;
persistent default_params
if isempty(default_params)
    default_params = parse_print_to___get_default;
    default_params = default_params.params;
end
if isempty(item),item=struct;end
if ~isa(item,'struct'),ErrorFlag = true;item = default_params;return,end
while true
    try MExc = []; %#ok<NASGU>
        [item,replaced] = parse_NameValue(default_params,item);
        break
    catch MExc;if isempty(MExc),MExc = lasterror;end %#ok<LERR>
        ErrorFlag = true;
        % Remove offending field as option and retry. This will terminate, as removing all
        % fields will result in replacing the struct with the default.
        item = rmfield(item,MExc.message);
    end
end
for n=1:numel(replaced)
    p = replaced{n};
    switch p
        case 'ShowTraceInMessage'
            [passed,item.(p)] = test_if_scalar_logical(item.(p));
            if ~passed
                ErrorFlag=true;
                item.(p) = default_params.(p);
            end
        case 'WipeTraceForBuiltin'
            [passed,item.(p)] = test_if_scalar_logical(item.(p));
            if ~passed
                ErrorFlag=true;
                item.(p) = default_params.(p);
            end
    end
end
end
function [success,opts,ME,ReturnFlag,replaced]=parse_varargin_robust(default,varargin)
% This function will parse the optional input arguments. If any error occurs, it will attempt to
% parse the exception redirection parameters before returning.

% Pre-assign output.
success = false;
ReturnFlag = false;
ME = struct('identifier','','message','');
replaced = cell(0);

try ME_ = [];[opts,replaced] = parse_NameValue(default,varargin{:}); %#ok<NASGU>
catch ME_;if isempty(ME_),ME_ = lasterror;end,ME = ME_;ReturnFlag=true;end %#ok<LERR>

if ReturnFlag
    % The normal parsing failed. We should still attempt to convert the input to a struct if it
    % isn't already, so we can attempt to parse the error redirection options.
    if isa(varargin{1},'struct')
        % Copy the input struct to this variable.
        opts = varargin{1};
    else
        % Attempt conversion from Name,Value to struct.
        try
            opts = struct(varargin{:});
        catch
            % Create an empty struct to make sure the variable exists.
            opts = struct;
        end
    end
    
    % Parse any relevant settings if possible.
    if isfield(opts,'print_to')
        print_to = opts.print_to;
    else
        print_to = parse_print_to___named_fields_to_struct(opts);
    end
else
    % The normal parsing worked as expected. If print_to was provided as a field, we should use
    % that one instead of the named print_to_ options.
    if ismember('print_to',replaced)
        print_to = opts.print_to;
    else
        print_to = parse_print_to___named_fields_to_struct(opts);
    end
end

% Attempt to parse the error redirection options (this generates an ME struct on fail) and validate
% the chosen parameters so we avoid errors in warning_ or error_.
[isValid,ME__print_to,opts.print_to] = parse_print_to___validate_struct(print_to);
if ~isValid,ME = ME__print_to;ReturnFlag = true;end
end
function [id,msg,stack,trace,no_op]=parse_warning_error_redirect_inputs(varargin)
no_op = false;
if nargin==1
    %  error_(options,msg)
    %  error_(options,ME)
    if isa(varargin{1},'struct') || isa(varargin{1},'MException')
        ME = varargin{1};
        if numel(ME)~=1
            no_op = true;
            [id,msg,stack,trace] = deal('');
            return
        end
        try
            stack = ME.stack; % Use the original call stack if possible.
            trace = get_trace(0,stack);
        catch
            [trace,stack] = get_trace(3);
        end
        id = ME.identifier;
        msg = ME.message;
        % This line will only appear on older releases.
        pat = 'Error using ==> ';
        if strcmp(msg(1:min(end,numel(pat))),pat)
            % Look for the first newline to strip the entire first line.
            ind = min(find(ismember(double(msg),[10 13]))); %#ok<MXFND> 
            if any(double(msg(ind+1))==[10 13]),ind = ind-1;end
            msg(1:ind) = '';
        end
        pat = 'Error using <a href="matlab:matlab.internal.language.introspective.errorDocCallbac';
        % This pattern may occur when using try error(id,msg),catch,ME=lasterror;end instead of
        % catching the MException with try error(id,msg),catch ME,end.
        % This behavior is not stable enough to robustly check for it, but it only occurs with
        % lasterror, so we can use that.
        if isa(ME,'struct') && strcmp( pat , msg(1:min(end,numel(pat))) )
            % Strip the first line (which states 'error in function (line)', instead of only msg).
            msg(1:min(find(msg==10))) = ''; %#ok<MXFND>
        end
    else
        [trace,stack] = get_trace(3);
        [id,msg] = deal('',varargin{1});
    end
else
    [trace,stack] = get_trace(3);
    if ~isempty(strfind(varargin{1},'%')) % The id can't contain a percent symbol.
        %  error_(options,msg,A1,...,An)
        id = '';
        A1_An = varargin(2:end);
        msg = sprintf(varargin{1},A1_An{:});
    else
        %  error_(options,id,msg)
        %  error_(options,id,msg,A1,...,An)
        id = varargin{1};
        msg = varargin{2};
        if nargin>2
            A1_An = varargin(3:end);
            msg = sprintf(msg,A1_An{:});
        end
    end
end
end
function opts=parse_warning_error_redirect_options(opts)
% The input is either:
% - an empty struct
% - the long form struct (with fields names 'print_to_')
% - the short hand struct (the print_to struct with the fields 'boolean', 'fid', etc)
%
% The returned struct will be a validated short hand struct.

if ...
        isfield(opts,'boolean') && ...
        isfield(opts.boolean,'IsValidated') && ...
        opts.boolean.IsValidated
    % Do not re-check a struct that self-reports to be validated.
    return
end

try
    % First, attempt to replace the default values with the entries in the input struct.
    % If the input is the long form struct, this will fail.
    print_to = parse_NameValue(parse_print_to___get_default,opts);
    print_to.boolean.IsValidated = false;
catch
    % Apparently the input is the long form struct, and therefore should be parsed to the short
    % form struct, after which it can be validated.
    print_to = parse_print_to___named_fields_to_struct(opts);
end

% Now we can validate the struct. Here we will ignore any invalid parameters, replacing them with
% the default settings.
[ignore,ignore,opts] = parse_print_to___validate_struct(print_to); %#ok<ASGLU> 
end
function out=PatternReplace(in,pattern,rep)
%Functionally equivalent to strrep, but extended to more data types.
% Any input is coverted to a row vector.

in = reshape(in,1,[]);
out = in;
if numel(pattern)==0 || numel(pattern)>numel(in)
    % Return input unchaged (apart from the reshape), as strrep does as well.
    return
end

L = true(size(in));
L((end-numel(pattern)+2):end) = false; % Avoid partial matches
for n=1:numel(pattern)
    % For every element of the pattern, look for matches in the data. Keep track of all possible
    % locations of a match by shifting the logical vector.
    % The last n elements should be left unchanged, to avoid false positives with a wrap-around.
    L_n = in==pattern(n);
    L_n = circshift(L_n,[0 1-n]);
    L_n(1:(n-1)) = L(1:(n-1));
    L = L & L_n;
    
    % If there are no matches left (even if n<numel(pat)), the process can be aborted.
    if ~any(L),return,end
end

if numel(rep)==0
    out(L)=[];
    return
end

% For the replacement, we will create a shadow copy with a coded char array. Non-matching values
% will be coded with a space, the first character of a match will be encoded with an asterisk, and
% trailing characters will be encoded with an underscore.
% In the next step, regexprep will be used to perform the replacement, after which indexing can be
% used to compose the final array.
if numel(pattern)>1
    idx = bsxfun_plus(find(L),reshape(1:(numel(pattern)-1),[],1));
else
    idx = find(L);
end
idx = reshape(idx,1,[]);
str = repmat(' ',1,numel(in));
str(idx) = '_';
str( L ) = '*';
NonMatchL = str==' ';

% The regular expression will take care of the lazy pattern matching. This also shifts the number
% of underscores to the length of the replacement array.
str = regexprep(str,'\*_*',['*' repmat('_',1,numel(rep)-1)]);

% We can paste in the non-matching positions. Postitions where the replacement should be inserted
% may or may not be correct.
out(str==' ') = in(NonMatchL);

% Now we can paste in all the replacements.
x = strfind(str,'*');
idx = bsxfun_plus(x,reshape(0:(numel(rep)-1),[],1));
idx = reshape(idx,1,[]);
out(idx) = repmat(rep,1,numel(x));

% Remove the elements beyond the range of what the resultant array should be.
out((numel(str)+1):end) = [];
end
function out=PatternReplace_orginal(in,pattern,rep)
%Functionally equivalent to strrep, but extended to more data types.
out = in(:)';
if numel(pattern)==0
    L = false(size(in));
elseif numel(rep)>numel(pattern)
    error('not implemented (padding required)')
else
    L = true(size(in));
    for n=1:numel(pattern)
        k = find(in==pattern(n));
        k = k-n+1;k(k<1) = [];
        % Now k contains the indices of the beginning of each match.
        L2 = false(size(L));L2(k) = true;
        L = L & L2;
        if ~any(L),break,end
    end
end
k = find(L);
if ~isempty(k)
    for n=1:numel(rep)
        out(k+n-1) = rep(n);
    end
    if numel(rep)==0,n = 0;end
    if numel(pattern)>n
        k = k(:); % Enforce vector shape and direction.
        remove = (n+1):numel(pattern);
        idx = bsxfun_plus(k,remove-1);
        idx(ismember(idx,k)) = []; % Avoid removing inserted patterns.
        out(idx(:)) = [];
    end
end
end
function str=readfile_from_file(filename,LineEnding,print_2,err_on_ANSI)
persistent isOctave,if isempty(isOctave),isOctave = ifversion('<',0,'Octave','>',0);end
persistent ME_file_access_FormatSpec
if isempty(ME_file_access_FormatSpec)
    if isOctave,runtime = 'Octave';else,runtime = 'Matlab';end
    ME_file_access_FormatSpec = sprintf(['%s could not read the file %%s.\n',...
        'The file doesn''t exist or is not readable.\n',...
        '(Note that for online files, only http and https is supported.)'],runtime);
end
ME_file_access = struct('identifier','HJW:readfile:ReadFail','message',...
    sprintf(ME_file_access_FormatSpec,filename));

fid = fopen(filename,'rb');
if fid<0,error_(print_2,ME_file_access),end
data = fread(fid,'uint8=>uint8');
fclose(fid);
data = data.';
try ME = []; %#ok<NASGU>
    isUTF8 = true;
    converted = UTF8_to_unicode(data);
catch ME;if isempty(ME),ME = lasterror;end %#ok<LERR>
    if strcmp(ME.identifier,'HJW:UTF8_to_unicode:notUTF8')
        isUTF8 = false;
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
        str = converted;
    else
        try str = fileread(filename);catch,error_(print_2,ME_file_access),end
        str = convert_from_codepage(str);
    end
else
    if ispc
        if isUTF8
            str = converted;
        else
            if ifversion('<',7)
                try str = fileread(filename);catch,error_(print_2,ME_file_access),end
                str = convert_from_codepage(str);
            else
                try str = fileread(filename);catch,error_(print_2,ME_file_access),end
            end
        end
    else % This assumes Mac will work the same as Linux.
        if isUTF8
            str = converted;
        else
            str = convert_from_codepage(data);
        end
    end
end

% Remove UTF BOM (U+FEFF) from text.
if numel(str)>=1 && double(str(1))==65279,str(1) = [];end
% Convert back to a char and split to a cellstr.
str = unicode_to_char(str);
if isa(LineEnding,'double') && isempty(LineEnding)
    str = char2cellstr(str);
else
    str = char2cellstr(str,LineEnding);
end
end
function str=readfile_from_URL(url,UseURLread,print_to,LineEnding,err_on_ANSI,webopts)
%Read the contents of a file to a char array.
%
% Attempt to download to the temp folder, read the file, then delete it.
% If that fails, read to a char array with urlread/webread.
try
    RevertToUrlread=false; % In case the saving+reading fails.
    % Generate a random file name in the temp folder.
    fn = tmpname('readfile_from_URL_tmp_','.txt');
    try
        % Try to download with 'raw' (or 'text') as ContentType to prevent parsing of XML/JSON/etc.
        if UseURLread,fn = urlwrite(url,fn); %#ok<URLWR>
        else,         fn =  websave(fn,url,webopts);end
        
        % Try to read.
        str = readfile_from_file(fn,LineEnding,print_to,err_on_ANSI);
    catch
        RevertToUrlread = true;
    end
    
    % Delete the temp file.
    try if exist(fn,'file'),delete(fn);end,catch,end
    
    if RevertToUrlread,error('revert to urlread'),end
catch
    % Read to a char array and let these functions throw an error in case of HTML errors and/or
    % missing connectivity.
    try ME = []; %#ok<NASGU>
        % Use 'raw' as ContentType to prevent parsing of XML/JSON/etc by webread.
        if UseURLread,str = urlread(url);else%#ok<URLRD>
            str = webread(url,webopts);end
    catch ME;if isempty(ME),ME = lasterror;end %#ok<LERR>
        error_(print_to,ME)
    end
end
end
function [success,opts,ME]=readfile_parse_inputs(filename,varargin)
%Parse the inputs of the readfile function
% It returns a success flag, the parsed options, and an ME struct.
% As input, the options should either be entered as a struct or as Name,Value pairs. Missing fields
% are filled from the default.

default = readfile_parse_inputs_defaults;
% Attempt to match the inputs to the available options. This will return a struct with the same
% fields as the default option struct. If anything fails, an attempt will be made to parse the
% exception redirection options anyway.
[success,opts,ME,ReturnFlag,replaced] = parse_varargin_robust(default,varargin{:});
if ReturnFlag,return,end

% Test the required input.
[valid,filename] = filename_is_valid(filename); % This will covert string to char.
try
    opts.OfflineFile = ~ ...
        (  strcmpi(filename(1:min(end,7)),'http://') ...
        || strcmpi(filename(1:min(end,8)),'https://'));
    if opts.OfflineFile
        % Offline files must adhere to the standards of the is_valid check and can be check by the
        % exist function.
        if ~exist(filename,'file'),valid = false;end
        if ~valid,error('trigger'),end
    else
        % Test if it is long enough to be a proper URL.
        if numel(filename)<10,error('trigger'),end
    end
    % Add the input to the struct.
    opts.filename = filename;
catch
    ME.identifier = 'HJW:readfile:IncorrectInput';
    ME.message = 'The file must exist and the name must be a non-empty char or a scalar string.';
    return
end

if numel(replaced)==0,success = true;ME = [];return,end % no default values were changed

% Check optional inputs.
for k=1:numel(replaced)
    item = opts.(replaced{k});
    ME.identifier = ['HJW:readfile:incorrect_input_opt_' lower(replaced{k})];
    switch replaced{k}
        case {'print_to_con','print_to_fid','print_to_obj','print_to_fcn'}
            % Already checked.
        case 'UseURLread'
            [passed,item] = test_if_scalar_logical(item);
            if ~passed
                ME.message = 'UseURLread should be either true or false';
                return
            end
            % Force the use of urlread/urlwrite if websave/webread are not available.
            opts.UseURLread = item || default.UseURLread;
        case 'err_on_ANSI'
            [passed,item] = test_if_scalar_logical(item);
            if ~passed
                ME.message = 'err_on_ANSI should be either true or false';
                return
            end
            opts.err_on_ANSI = item;
        case 'EmptyLineRule'
            if isa(item,'string')
                if numel(item)~=1,item = []; % This will trigger an error.
                else,item = char(item);end   % Convert a scalar string to char.
            end
            if isa(item,'char'),item = lower(item);end
            if ~isa(item,'char') || ...
                    ~ismember(item,{'read','skip','error','skipleading','skiptrailing'})
                ME.message = 'EmptyLineRule must be a char or string with a specific value.';
                return
            end
            opts.EmptyLineRule = item;
        case 'Whitespace'
            % Cellstr input is converted to a char array with sprintf.
            try
                switch class(item)
                    case 'string'
                        if numel(item)~=1,error('trigger error'),end
                        item = char(item);
                    case 'cell'
                        for n=1:numel(item),item{n} = sprintf(item{n});end
                        item = horzcat(item{:});
                    case 'char'
                        % Nothing to check or do here.
                    otherwise
                        error('trigger error')
                end
                opts.Whitespace = item;
            catch
                ME.message = ['The Whitespace parameter must be a char vector, string scalar ',...
                    'or cellstr.\nA cellstr input must be parsable by sprintf.'];
                return
            end
        case 'WhitespaceRule'
            if isa(item,'string')
                if numel(item)~=1,item = []; % This will trigger an error.
                else,item = char(item);end   % Convert a scalar string to char.
            end
            if isa(item,'char'),item = lower(item);end
            if ~isa(item,'char') || ...
                    ~ismember(item,{'preserve','trim','trimleading','trimtrailing'})
                ME.message = 'WhitespaceRule must be a char or string with a specific value.';
                return
            end
            opts.WhitespaceRule = item;
        case 'LineEnding'
            %character vector  - literal
            %string scalar  - literal
            %cell array of character vectors  - parse by sprintf
            %string array  - parse by sprintf
            err = false;
            if isa(item,'string')
                item = cellstr(item);
                if numel(item)==1,item = item{1};end % Convert scalar string to char.
            end
            if isa(item,'cell')
                try for n=1:numel(item),item{n} = sprintf(item{n});end,catch,err = true;end
            elseif isa(item,'char')
                item = {item};% Wrap char in a cell.
            else
                err = true; % This catches [] as well, while iscellstr wouldn't.
            end
            if err || ~iscellstr(item)
                ME.message = ['The LineEnding parameter must be a char vector, a string or a ',...
                    'cellstr.\nA cellstr or string vector input must be parsable by sprintf.'];
                return
            end
            if isequal(item,{char(10) char(13) char([13 10])}) %#ok<CHARTEN>
                opts.LineEnding = [];
            else
                opts.LineEnding = item;
            end
        case 'UseReadlinesDefaults'
            [passed,item] = test_if_scalar_logical(item);
            if ~passed
                ME.message = 'UseReadlinesDefaults should be either true or false';
                return
            end
            opts.UseReadlinesDefaults = item;
        case 'weboptions'
            % The UseURLread default will only be true weboptions exists. If it doesn't, don't
            % bother checking the validity.
            if ~opts.OfflineFile && ~default.UseURLread
                fail = false;
                if ~isa(item,class(weboptions))
                    % The input class doesn't match what the function is returning.
                    fail = true;
                else
                    % Attempt to copy over either 'raw' or 'text'.
                    try   item.ContentType = default.weboptions.ContentType;
                    catch,fail = true;
                    end
                end
                if fail
                    ME.message = 'weboptions input is not valid';
                    return
                end
            end
            
    end
end

if opts.UseReadlinesDefaults
    fn = fieldnames(default.ReadlinesDefaults);
    for n=1:numel(fn)
        opts.(fn{n}) = default.ReadlinesDefaults.(fn{n});
    end
end

success = true;ME = [];
end
function opts=readfile_parse_inputs_defaults
% Create a struct with default values.
persistent opts_
if isempty(opts_)
    legacy.allows_https = hasFeature('HTTPS_support');
    opts_.legacy = legacy;
    % Test if either webread(), websave(), or weboptions() are missing.
    try no_webread = isempty(which(func2str(@webread   )));catch,no_webread = true;end
    try no_websave = isempty(which(func2str(@websave   )));catch,no_websave = true;end
    try no_webopts = isempty(which(func2str(@weboptions)));catch,no_webopts = true;end
    opts_.UseURLread = no_webread || no_websave || no_webopts;
    
    opts_.print_to_con = [];
    opts_.print_to_fid = [];
    opts_.print_to_obj = [];
    opts_.print_to_fcn = [];
    opts_.print_to_params = [];
    [opts_.print_to,print_to_option__field_names_in] = parse_print_to___get_default;
    for n=1:numel(print_to_option__field_names_in)
        opts_.(print_to_option__field_names_in{n})=[];
    end
    
    opts_.err_on_ANSI = false;
    % readlines has a bug where it fails for chars outside the BMP (e.g. most emoji).
    opts_.FailMultiword_UTF16 = false;
    opts_.EmptyLineRule = 'read';
    % The Whitespace parameter contains most characters reported by isspace, plus delete characters
    % and no break spaces. This is different from the default for readlines.
    % To make sure all these code points are encoded in char correctly, we need to use
    % unicode_to_char. The reason for this is that Octave uses UTF-8.
    opts_.Whitespace = unicode_to_char([8 9 28:32 160 5760 8192:8202 8239 8287 12288]);
    opts_.DefaultLineEnding = true;
    opts_.LineEnding = [];%(equivalent to {'\r\n','\n','\r'}, the order matters for char2cellstr)
    opts_.WhitespaceRule = 'preserve';
    if no_webopts
        opts_.weboptions = struct('ContentType','raw');
    else
        try
            opts_.weboptions = weboptions('ContentType','raw');
        catch
            opts_.weboptions = weboptions('ContentType','text');
        end
    end
    
    % Replace with ifversion when the flag for the bug should become false.
    opts_.UseReadlinesDefaults = false;
    opts_.ReadlinesDefaults.FailMultiword_UTF16 = true;
    opts_.ReadlinesDefaults.Whitespace = sprintf(' \b\t');
end
opts = opts_;
end
function [isLogical,val]=test_if_scalar_logical(val)
%Test if the input is a scalar logical or convertible to it.
% The char and string test are not case sensitive.
% (use the first output to trigger an input error, use the second as the parsed input)
%
%  Allowed values:
% - true or false
% - 1 or 0
% - 'on' or 'off'
% - "on" or "off"
% - matlab.lang.OnOffSwitchState.on or matlab.lang.OnOffSwitchState.off
% - 'enable' or 'disable'
% - 'enabled' or 'disabled'
persistent states
if isempty(states)
    states = {...
        true,false;...
        1,0;...
        'on','off';...
        'enable','disable';...
        'enabled','disabled'};
    % We don't need string here, as that will be converted to char.
end

% Treat this special case.
if isa(val,'matlab.lang.OnOffSwitchState')
    isLogical = true;val = logical(val);return
end

% Convert a scalar string to char and return an error state for non-scalar strings.
if isa(val,'string')
    if numel(val)~=1,isLogical = false;return
    else            ,val = char(val);
    end
end

% Convert char/string to lower case.
if isa(val,'char'),val = lower(val);end

% Loop through all possible options.
for n=1:size(states,1)
    for m=1:2
        if isequal(val,states{n,m})
            isLogical = true;
            val = states{1,m};
            return
        end
    end
end

% Apparently there wasn't any match, so return the error state.
isLogical = false;
end
function str=tmpname(StartFilenameWith,ext)
% Inject a string in the file name part returned by the tempname function.
if nargin<1,StartFilenameWith = '';end
if ~isempty(StartFilenameWith),StartFilenameWith = [StartFilenameWith '_'];end
if nargin<2,ext='';else,if ~strcmp(ext(1),'.'),ext = ['.' ext];end,end
str = tempname;
[p,f] = fileparts(str);
str = fullfile(p,[StartFilenameWith f ext]);
end
function str=unicode_to_char(unicode,encode_as_UTF16)
%Encode Unicode code points with UTF-16 on Matlab and UTF-8 on Octave.
%
% Input is either implicitly or explicitly converted to a row-vector.

persistent isOctave,if isempty(isOctave),isOctave = ifversion('<',0,'Octave','>',0);end
if nargin==1
    encode_as_UTF16 = ~CharIsUTF8;
end
if encode_as_UTF16
    if all(unicode<65536)
        str = uint16(unicode);
        str = reshape(str,1,numel(str));%Convert explicitly to a row-vector.
    else
        % Encode as UTF-16.
        [char_list,ignore,positions] = unique(unicode); %#ok<ASGLU>
        str = cell(1,numel(unicode));
        for n=1:numel(char_list)
            str_element = unicode_to_UTF16(char_list(n));
            str_element = uint16(str_element);
            str(positions==n) = {str_element};
        end
        str = cell2mat(str);
    end
    if ~isOctave
        str = char(str); % Conversion to char could trigger a conversion range error in Octave.
    end
else
    if all(unicode<128)
        str = char(unicode);
        str = reshape(str,1,numel(str));% Convert explicitly to a row-vector.
    else
        % Encode as UTF-8.
        [char_list,ignore,positions] = unique(unicode); %#ok<ASGLU>
        str = cell(1,numel(unicode));
        for n=1:numel(char_list)
            str_element = unicode_to_UTF8(char_list(n));
            str_element = uint8(str_element);
            str(positions==n) = {str_element};
        end
        str = cell2mat(str);
        str = char(str);
    end
end
end
function str=unicode_to_UTF16(unicode)
% Convert a single character to UTF-16 bytes.
%
% The value of the input is converted to binary and padded with 0 bits at the front of the string
% to fill all 'x' positions in the scheme.
% See https://en.wikipedia.org/wiki/UTF-16
%
% 1 word (U+0000 to U+D7FF and U+E000 to U+FFFF):
%  xxxxxxxx_xxxxxxxx
% 2 words (U+10000 to U+10FFFF):
%  110110xx_xxxxxxxx 110111xx_xxxxxxxx
if unicode<65536
    str = unicode;return
end
U = double(unicode)-65536; % Cast to double to avoid an error in old versions of Matlab.
U = dec2bin(U,20);
str = bin2dec(['110110' U(1:10);'110111' U(11:20)]).';
end
function str=unicode_to_UTF8(unicode)
% Convert a single character to UTF-8 bytes.
%
% The value of the input is converted to binary and padded with 0 bits at the front of the string
% to fill all 'x' positions in the scheme.
% See https://en.wikipedia.org/wiki/UTF-8
if numel(unicode)>1,error('this should only be used for single characters'),end
if unicode<128
    str = unicode;return
end
persistent pers
if isempty(pers)
    pers = struct;
    pers.limits.lower = hex2dec({'0000','0080','0800', '10000'});
    pers.limits.upper = hex2dec({'007F','07FF','FFFF','10FFFF'});
    pers.scheme{2} = '110xxxxx10xxxxxx';
    pers.scheme{2} = reshape(pers.scheme{2}.',8,2);
    pers.scheme{3} = '1110xxxx10xxxxxx10xxxxxx';
    pers.scheme{3} = reshape(pers.scheme{3}.',8,3);
    pers.scheme{4} = '11110xxx10xxxxxx10xxxxxx10xxxxxx';
    pers.scheme{4} = reshape(pers.scheme{4}.',8,4);
    for b=2:4
        pers.scheme_pos{b} = find(pers.scheme{b}=='x');
        pers.bits(b) = numel(pers.scheme_pos{b});
    end
end
bytes = find(pers.limits.lower<=unicode & unicode<=pers.limits.upper);
str = pers.scheme{bytes};
scheme_pos = pers.scheme_pos{bytes};
% Cast to double to avoid an error in old versions of Matlab.
b = dec2bin(double(unicode),pers.bits(bytes));
str(scheme_pos) = b;
str = bin2dec(str.').';
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
UTF16 = uint32(UTF16);

multiword = UTF16>55295 & UTF16<57344; % 0xD7FF and 0xE000
if ~any(multiword)
    unicode = UTF16;return
end

word1 = find( UTF16>=55296 & UTF16<=56319 );
word2 = find( UTF16>=56320 & UTF16<=57343 );
try
    d = word2-word1;
    if any(d~=1) || isempty(d)
        error('trigger error')
    end
catch
    error('input is not valid UTF-16 encoded')
end

%Binary header:
% 110110xx_xxxxxxxx 110111xx_xxxxxxxx
% 00000000 01111111 11122222 22222333
% 12345678 90123456 78901234 56789012
header_bits = '110110110111';header_locs=[1:6 17:22];
multiword = UTF16([word1.' word2.']);
multiword = unique(multiword,'rows');
S2 = mat2cell(multiword,ones(size(multiword,1),1),2);
unicode = UTF16;
for n=1:numel(S2)
    bin = dec2bin(double(S2{n}))';
    
    if ~strcmp(header_bits,bin(header_locs))
        error('input is not valid UTF-16 encoded')
    end
    bin(header_locs) = '';
    if ~isOctave
        S3 = uint32(bin2dec(bin  ));
    else
        S3 = uint32(bin2dec(bin.'));%Octave needs an extra transpose.
    end
    S3 = S3+65536;% 0x10000
    % Perform actual replacement.
    unicode = PatternReplace(unicode,S2{n},S3);
end
end
function [unicode,isUTF8,assumed_UTF8]=UTF8_to_unicode(UTF8,print_to)
%Convert UTF-8 to the code points stored as uint32
% Plane 16 goes up to 10FFFF, so anything larger than uint16 will be able to hold every code point.
%
% If there a second output argument, this function will not return an error if there are encoding
% error. The second output will contain the attempted conversion, while the first output will
% contain the original input converted to uint32.
%
% The second input can be used to also print the error to a GUI element or to a text file.
if nargin<2,print_to = [];end
return_on_error = nargout==1 ;

UTF8 = uint32(reshape(UTF8,1,[]));% Force row vector.
[assumed_UTF8,flag,ME] = UTF8_to_unicode_internal(UTF8,return_on_error);
if strcmp(flag,'success')
    isUTF8 = true;
    unicode = assumed_UTF8;
elseif strcmp(flag,'error')
    isUTF8 = false;
    if return_on_error
        error_(print_to,ME)
    end
    unicode = UTF8; % Return input unchanged (apart from casting to uint32).
end
end
function [UTF8,flag,ME]=UTF8_to_unicode_internal(UTF8,return_on_error)
flag = 'success';
ME = struct('identifier','HJW:UTF8_to_unicode:notUTF8','message','Input is not UTF-8.');

persistent isOctave,if isempty(isOctave),isOctave = ifversion('<',0,'Octave','>',0);end

if any(UTF8>255)
    flag = 'error';
    if return_on_error,return,end
elseif all(UTF8<128)
    return
end

for bytes=4:-1:2
    val = bin2dec([repmat('1',1,bytes) repmat('0',1,8-bytes)]);
    multibyte = UTF8>=val & UTF8<256; % Exclude the already converted chars.
    if any(multibyte)
        multibyte = find(multibyte);multibyte=multibyte(:).';
        if numel(UTF8)<(max(multibyte)+bytes-1)
            flag = 'error';
            if return_on_error,return,end
            multibyte( (multibyte+bytes-1)>numel(UTF8) ) = [];
        end
        if ~isempty(multibyte)
            idx = bsxfun_plus(multibyte , (0:(bytes-1)).' );
            idx = idx.';
            multibyte = UTF8(idx);
        end
    else
        multibyte = [];
    end
    header_bits = [repmat('1',1,bytes-1) repmat('10',1,bytes)];
    header_locs = unique([1:(bytes+1) 1:8:(8*bytes) 2:8:(8*bytes)]);
    if numel(multibyte)>0
        multibyte = unique(multibyte,'rows');
        S2 = mat2cell(multibyte,ones(size(multibyte,1),1),bytes);
        for n=1:numel(S2)
            bin = dec2bin(double(S2{n}))';
            % To view the binary data, you can use this: bin=bin(:)';
            % Remove binary header (3 byte example):
            % 1110xxxx10xxxxxx10xxxxxx
            %     xxxx  xxxxxx  xxxxxx
            if ~strcmp(header_bits,bin(header_locs))
                % Check if the byte headers match the UTF-8 standard.
                flag = 'error';
                if return_on_error,return,end
                continue %leave unencoded
            end
            bin(header_locs) = '';
            if ~isOctave
                S3 = uint32(bin2dec(bin  ));
            else
                S3 = uint32(bin2dec(bin.'));% Octave needs an extra transpose.
            end
            % Perform actual replacement.
            UTF8 = PatternReplace(UTF8,S2{n},S3);
        end
    end
end
end
function warning_(options,varargin)
%Print a warning to the command window, a file and/or the String property of an object
% The lastwarn state will be set if the warning isn't thrown with warning().
% The printed call trace omits this function, but the warning() call does not.
%
% Apart from controlling the way an error is written, you can also run a specific function. The
% 'fcn' field of the options must be a struct (scalar or array) with two fields: 'h' with a
% function handle, and 'data' with arbitrary data passed as third input. These functions will be
% run with 'warning' as first input. The second input is a struct with identifier, message, and
% stack as fields. This function will be run with feval (meaning the function handles can be
% replaced with inline functions or anonymous functions).
%
% The intention is to allow replacement of most warning(___) call with warning_(options,___). This
% does not apply to calls that query or set the warning state.
%
% NB: the function trace that is written to a file or object may differ from the trace displayed by
% calling the builtin error/warning functions (especially when evaluating code sections). The
% calling code will not be included in the constructed trace.
%
% There are two ways to specify the input options. The shorthand struct described below can be used
% for fast repeated calls, while the input described below allows an input that is easier to read.
% Shorthand struct:
%  options.boolean.IsValidated: if true, validation is skipped
%  options.params:              optional parameters for error_ and warning_, as explained below
%  options.boolean.con:         only relevant for warning_, ignored
%  options.fid:                 file identifier for fprintf (array input will be indexed)
%  options.boolean.fid:         if true print error to file
%  options.obj:                 handle to object with String property (array input will be indexed)
%  options.boolean.obj:         if true print error to object (options.obj)
%  options.fcn                  struct (array input will be indexed)
%  options.fcn.h:               handle of function to be run
%  options.fcn.data:            data passed as third input to function to be run (optional)
%  options.boolean.fnc:         if true the function(s) will be run
%
% Full input description:
%   print_to_con:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      A logical that controls whether warnings and other output will be printed to the command
%      window. Errors can't be turned off. [default=true;]
%      Specifying print_to_fid, print_to_obj, or print_to_fcn will change the default to false,
%      unless parsing of any of the other exception redirection options results in an error.
%   print_to_fid:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      The file identifier where console output will be printed. Errors and warnings will be
%      printed including the call stack. You can provide the fid for the command window (fid=1) to
%      print warnings as text. Errors will be printed to the specified file before being actually
%      thrown. [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_obj:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      The handle to an object with a String property, e.g. an edit field in a GUI where console
%      output will be printed. Messages with newline characters (ignoring trailing newlines) will
%      be returned as a cell array. This includes warnings and errors, which will be printed
%      without the call stack. Errors will be written to the object before the error is actually
%      thrown. [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_fcn:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      A struct with a function handle, anonymous function or inline function in the 'h' field and
%      optionally additional data in the 'data' field. The function should accept three inputs: a
%      char array (either 'warning' or 'error'), a struct with the message, id, and stack, and the
%      optional additional data. The function(s) will be run before the error is actually thrown.
%      [default=[];]
%      If print_to_fid, print_to_obj, and print_to_fcn are all empty, this will have the effect of
%      suppressing every output except errors.
%      Array inputs are allowed.
%   print_to_params:
%      NB: An attempt is made to use this parameter for warnings or errors during input parsing.
%      This struct contains the optional parameters for the error_ and warning_ functions.
%      Each field can also be specified as ['print_to_option_' parameter_name]. This can be used to
%      avoid nested struct definitions.
%      ShowTraceInMessage:
%        [default=false] Show the function trace in the message section. Unlike the normal results
%        of rethrow/warning, this will not result in clickable links.
%      WipeTraceForBuiltin:
%        [default=false] Wipe the trace so the rethrow/warning only shows the error/warning message
%        itself. Note that the wiped trace contains the calling line of code (along with the
%        function name and line number), while the generated trace does not.
%
% Syntax:
%   warning_(options,msg)
%   warning_(options,msg,A1,...,An)
%   warning_(options,id,msg)
%   warning_(options,id,msg,A1,...,An)
%   warning_(options,ME)               %rethrow error as warning
%
%examples options struct:
%  % Write to a log file:
%  opts=struct;opts.fid=fopen('log.txt','wt');
%  % Display to a status window and bypass the command window:
%  opts=struct;opts.boolean.con=false;opts.obj=uicontrol_object_handle;
%  % Write to 2 log files:
%  opts=struct;opts.fid=[fopen('log2.txt','wt') fopen('log.txt','wt')];

persistent this_fun
if isempty(this_fun),this_fun = func2str(@warning_);end

% Parse options struct, allowing an empty input to revert to default.
if isempty(options),options = struct;end
options                    = parse_warning_error_redirect_options(  options  );
[id,msg,stack,trace,no_op] = parse_warning_error_redirect_inputs( varargin{:});

% Don't waste time parsing the options in case of a no-op.
if no_op,return,end
% Check if the warning is turned off and exit the function if this is the case.
w = warning;if any(ismember({w(ismember({w.identifier},{id,'all'})).state},'off')),return,end

% Check whether we need to include the trace in the warning message.
backtrace = warning('query','backtrace');if strcmp(backtrace.state,'off'),trace = '';end

if options.params.ShowTraceInMessage && ~isempty(trace)
    msg = sprintf('%s\n%s',msg,trace);
end
if options.params.WipeTraceForBuiltin && strcmp(backtrace.state,'on')
    warning('off','backtrace')
end

if options.boolean.con
    % Always omit the verbosity statement ("turn this warning off with ___").
    x = warning('query','verbose');if strcmp(x.state,'on'),warning('off','verbose'),end
    if ~isempty(id),warning(id,'%s',msg),else,warning(msg), end
    % Restore verbosity setting.
    if strcmp(x.state,'on'),warning('on','verbose'),end
else
    if ~isempty(id),lastwarn(msg,id);    else,lastwarn(msg),end
end
% Reset the backtrace state as soon as possible.
if options.params.WipeTraceForBuiltin && strcmp(backtrace.state,'on')
    warning('on','backtrace')
end
    
if options.boolean.obj
    msg_ = msg;while msg_(end)==10,msg_(end)=[];end % Crop trailing newline.
    if any(msg_==10)  % Parse to cellstr and prepend warning.
        msg_ = char2cellstr(['Warning: ' msg_]);
    else              % Only prepend warning.
        msg_ = ['Warning: ' msg_];
    end
    set(options.obj,'String',msg_)
    for OBJ=options.obj(:).'
        try set(OBJ,'String',msg_);catch,end
    end
end

if options.boolean.fid
    T = datestr(now,31); %#ok<DATST,TNOW1> Print the time of the warning to the log as well.
    for FID=options.fid(:).'
        try fprintf(FID,'[%s] Warning: %s\n%s',T,msg,trace);catch,end
    end
end

if options.boolean.fcn
    if ismember(this_fun,{stack.name})
        % To prevent an infinite loop, trigger an error.
        error('prevent recursion')
    end
    ME = struct('identifier',id,'message',msg,'stack',stack);
    for FCN=options.fcn(:).'
        if isfield(FCN,'data')
            try feval(FCN.h,'warning',ME,FCN.data);catch,end
        else
            try feval(FCN.h,'warning',ME);catch,end
        end
    end
end
end

