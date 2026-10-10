function ok = test_toolbox()
%TEST_TOOLBOX  Minimal self-check of the bundled MRST subtree.
%
%   >> test_toolbox
%
% Verifies that the trimmed MRST copy in libs/mrst provides everything the
% drivers in src/ need, without requiring any field data:
%
%   1. the five MRST entry functions resolve on the MATLAB path;
%   2. readGRDECL / writeGRDECL round-trip on examples/tiny.GRDECL;
%   3. readEclipseOutputFileUnFmt parses examples/tiny.SLNSPEC (a miniature
%      Eclipse unformatted result file, same container format as .SLNSPEC /
%      .SLNxxxx produced by the simulator);
%   4. file2Streamline is on the path.
%
% A full-field check (grid build + real streamlines) needs real Eclipse files
% and is described in ../docs/dependencies.md.

   here  = fileparts(mfilename('fullpath'));
   repo  = fileparts(here);
   ok    = true;

   fprintf('== test_toolbox ===========================================\n');

   % ---------------------------------------------------------------- 1
   fprintf('\n[1] MRST entry functions on the path\n');
   fns = {'readGRDECL','writeGRDECL','processGRDECL','computeGeometry', ...
          'readEclipseOutputFileUnFmt'};
   for i = 1:numel(fns)
      w = which(fns{i});
      if isempty(w)
         fprintf('    MISSING  %s\n', fns{i});  ok = false;
      else
         fprintf('    ok       %-28s %s\n', fns{i}, shorten(w, repo));
      end
   end

   % ---------------------------------------------------------------- 2
   fprintf('\n[2] readGRDECL -> writeGRDECL -> readGRDECL round trip\n');
   try
      g = readGRDECL(fullfile(here,'tiny.GRDECL'));
      fprintf('    read:      cartDims=%s  PERMX=%d  ACTNUM=%d\n', ...
              mat2str(g.cartDims(:)'), numel(g.PERMX), numel(g.ACTNUM));

      g2 = g;  g2.PERMX = g.PERMX * 1.5;
      outFile = fullfile(tempdir, 'tiny_roundtrip.GRDECL');
      writeGRDECL(g2, outFile);
      g3 = readGRDECL(outFile, 'keywords', {'PERMX'});
      ok2 = numel(g3.PERMX) == numel(g.PERMX) && abs(g3.PERMX(1) - 1.5*g.PERMX(1)) < 1e-4;
      fprintf('    write+read: PERMX(1) %.2f -> %.2f (x1.5 expected)  %s\n', ...
              g.PERMX(1), g3.PERMX(1), verdict(ok2));
      delete(outFile);  ok = ok && ok2;
   catch ME
      fprintf('    ERROR: %s\n', ME.message);  ok = false;
   end

   % ---------------------------------------------------------------- 3
   fprintf('\n[3] readEclipseOutputFileUnFmt on a miniature .SLNSPEC\n');
   try
      o  = readEclipseOutputFileUnFmt(fullfile(here,'tiny.SLNSPEC'));
      ih = double(o.INTEHEAD.values(:)');
      sw = double(o.SWAT.values(:)');
      fprintf('    fields:    %s\n', strjoin(fieldnames(o)', ', '));
      fprintf('    INTEHEAD(%s) = %s\n', o.INTEHEAD.type, mat2str(ih));
      fprintf('    SWAT(%s)     = %s\n', o.SWAT.type, mat2str(sw, 4));
      ok3 = isequal(ih, [2020 6 15 1 1 1]) && all(abs(sw - [0.1 0.2 0.3 0.4]) < 1e-6);
      fprintf('    values match the file content: %s\n', verdict(ok3));
      ok = ok && ok3;
   catch ME
      fprintf('    ERROR: %s\n', ME.message);  ok = false;
   end

   % ---------------------------------------------------------------- 4
   fprintf('\n[4] file2Streamline on the path\n');
   w = which('file2Streamline');
   if isempty(w), fprintf('    MISSING\n'); ok = false;
   else,          fprintf('    ok       %s\n', shorten(w, repo)); end

   % ----------------------------------------------------------------
   fprintf('\n------------------------------------------------------------\n');
   if ok
      fprintf('ALL CHECKS PASSED.  The bundled MRST subtree is complete.\n');
   else
      fprintf('SOME CHECKS FAILED -- see the lines marked above.\n');
   end
   fprintf('============================================================\n');
end

% ---------------------------------------------------------------------
function s = shorten(full, repo)
   s = strrep(full, [repo filesep], '');
end

function s = verdict(b)
   if b, s = 'OK'; else, s = 'FAILED'; end
end
