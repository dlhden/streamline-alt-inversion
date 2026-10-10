function startup()
%STARTUP  Put this repository (and its bundled MRST subset) on the MATLAB path.
%
%   >> startup
%
% The drivers in src/ call five functions from MRST -- the MATLAB Reservoir
% Simulation Toolbox (SINTEF Digital, GPL-3.0):
%
%       readGRDECL, writeGRDECL, processGRDECL, computeGeometry,
%       readEclipseOutputFileUnFmt
%
% A *trimmed* copy of MRST that contains those functions and their complete
% dependency closure is bundled under libs/mrst, so no separate MRST
% installation is required.  See libs/README.md and docs/dependencies.md.
%
% If you already keep a full MRST installation on the MATLAB path you may run
% this script anyway (the bundled copy is added last and does not shadow a
% full installation that was added earlier), or simply delete libs/mrst.
%
% Released under the GNU General Public License v3.0.

   here = fileparts(mfilename('fullpath'));

   % ---- this repository -------------------------------------------------
   addpath(fullfile(here, 'src'));
   addpath(fullfile(here, 'examples'));

   % ---- bundled MRST subset --------------------------------------------
   mrstRoot = fullfile(here, 'libs', 'mrst');
   if exist(mrstRoot, 'dir') == 7
      p = strsplit(genpath(mrstRoot), pathsep);

      % The same directories are excluded as in MRST's own startup.m:
      % Octave-only shims (they shadow MATLAB built-ins), third-party
      % bundles, and version-control folders.
      keep = ~cellfun(@isempty, p)                                  ...
           & cellfun(@isempty, regexp(p, 'octave_only'))            ...
           & cellfun(@isempty, regexp(p, '3rdparty'))               ...
           & cellfun(@isempty, regexp(p, ['\' filesep '\.(git|hg|svn)']));

      addpath(p{keep});
      fprintf('Added %d folders from the bundled MRST subset.\n', nnz(keep));
   else
      warning(['libs/mrst not found -- install MRST separately and add it ' ...
               'to the MATLAB path before running the drivers.']);
   end

   fprintf(['streamline-alt-inversion is ready.\n' ...
            'Edit the "EDIT THIS BLOCK" section of a driver, then run e.g.  main_SL_inversion_C2\n']);
end
