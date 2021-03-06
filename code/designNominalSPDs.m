function resultSet = designNominalSPDs(varargin)
% Nominal primaries and SPDs for isolating post-receptoral mechanisms
%
% Syntax:
%	resultSet = designNominalSPDs
%
% Description:
%   This routine loads the tabular SPDs for a set of LEDs, and then
%   explores what mixture of n LEDs provides maximal contrast on specified
%   post-receptoral mechanisms, while simultaneously constraining the
%   differential contrast on jointly targeted mechanisms.
%
%   The particular application is selecting LEDs to be placed within a
%   device manufactured by the company Prizmatix. The output of the various
%   LEDs are combined by passing through dichroic mirrors. This has the
%   effect of filtering the SPDs of LEDs that are adjacent in peak
%   wavelength. This effect is modeled.
%
% Inputs:
%	None
%
% Outputs:
%	resultSet             - Struct. The primaries and SPDs.
%
% Optional key/value pairs:
%  'saveDir'              - Char. Full path to the directory in which the
%                           diagnostic plots will be saved. The directory
%                           will be created if it does not exist.
%  'ledSPDFileName'       - Char. Which table of LED primary SPDs to laod.
%  'primaryHeadRoom'      - Scalar. We can enforce a constraint that we
%                           don't go right to the edge of the gamut.  The
%                           head room parameter is defined in the [0-1]
%                           device primary space.  Using a little head room
%                           keeps us a bit away from the hard edge of the
%                           device.
%  'fieldSizeDegrees'     - Scalar
%  'pupilDiameterMm'      - Scalar
%  'observerAgeInYears'   - Scalar
%  'nLEDsToKeep'          - Scalar. The number of LEDs in the final device.
%  'minLEDspacing'        - Scalar. When picking sets of LEDs to examine,
%                           only use sets for which the peak wavelengths
%                           between the LEDs are all separated by at least
%                           this amount in nanometers.
%  'weightedBackgroundPrimaries' - Logical. When set to true, the
%                           background settings are inversely weighted by
%                           the total power of each LED.
%  'filterAdjacentPrimariesFlag' - Logical. When set to true, a logistic
%                           transmitance filter is applied to the SPD of
%                           adjacent LEDs to model the filtering effects
%                           of the dichroic mirrors.
%  'filterMaxSlopeParam'  - Scalar. The maximum slope of the logistic
%                           function that models the dichroic mirrors, in
%                           units of proportion filter / nm. The value of
%                           0.2 is pretty close to what is on the website
%                           for these filters.
%  'primariesToKeepBest'  - Vector. A set of LEDs that have been found to
%                           perform well in previous searches.
%  'nTests'               - Scalar. The number of permutations of LED sets
%                           to test for optimal performance. Set to inf to
%                           test all.
%  'stepSizeDiffContrastSearch' - Scalar. In searching for a modulation,
%                           routine attempts to maximize contrast on a
%                           targeted set of photoreceptors, but also
%                           attempts to minimize differential contrast on
%                           these. The targeted contrast is iteratively
%                           reduced until the differential contrast
%                           constraint is satisfied. This parameter sets
%                           how finely these iterative steps are taken.
%  'shrinkFactorThresh'   - Scalar. For this search across reduced contrast
%                           levels to minimize differential contrast, this
%                           sets the threshold at which we abandon the
%                           search and move on to a different set of
%                           primaries. If set to 0.7, for example, if the
%                           reduction in the desired contrast hits 70% of
%                           the original target, then we give up.
%
% Examples:
%{
    % These entries test our ability to replicate the SPD model used by the
    % Prizmatix engineers. There is some disagreement in the 4th primary
    % as I did not have access to the true SPD for that primary, and had
    % to assume the SPD and total power of the UHP-T-545-SR for the
    % UHP-T-545-LA21.
    ledSPDFileName = 'PrizmatixLED_SetA_SPDs.csv';
    ledTotalPowerFileName = 'PrizmatixLED_SetA_totalPower.csv';
    filterCenterWavelengthsBest = [423 453 506 575 610 649 685];
    primariesToKeepBest = 1:8; nTests = 1;
    resultSetOurs = designNominalSPDs('ledSPDFileName',ledSPDFileName,...
        'ledTotalPowerFileName',ledTotalPowerFileName,...
        'filterCenterWavelengthsBest',filterCenterWavelengthsBest,...
        'primariesToKeepBest',primariesToKeepBest,'nTests',nTests,...
        'makePlots',false);
    ledSPDFileName = 'PrizmatixLED_SetA_postFilter_SPDs.csv';
    ledTotalPowerFileName = 'PrizmatixLED_SetA_postFilter_totalPower.csv';
    filterCenterWavelengthsBest = [423 453 506 575 610 649 685];
    resultSetTheirs = designNominalSPDs('ledSPDFileName',ledSPDFileName,...
        'ledTotalPowerFileName',ledTotalPowerFileName,...
        'filterCenterWavelengthsBest',filterCenterWavelengthsBest,...
        'primariesToKeepBest',primariesToKeepBest,'nTests',nTests,...
        'makePlots',false);
    figure
    plot(resultSetTheirs.LMS.wavelengthsNm,resultSetTheirs.B_primary,'-','LineWidth',2); hold on
    plot(resultSetTheirs.LMS.wavelengthsNm,resultSetOurs.B_primary,'--','LineWidth',2);
%}

% Some good sets
%   [1 4 9 12 13 16 18 19] - the set that I sent to Nathaniel to model,
%   [1 3 6 10 12 13 16 19] - best set for Mel, with LED area modeled

%% Parse input
p = inputParser;
p.addParameter('saveDir','~/Desktop/nominalSPDs',@ischar);
p.addParameter('ledSPDFileName','PrizmatixLED_FullSet_SPDs.csv',@ischar);
p.addParameter('ledTotalPowerFileName','PrizmatixLED_FullSet_totalPower.csv',@ischar);
p.addParameter('primaryHeadRoom',0.05,@isscalar)
p.addParameter('observerAgeInYears',25,@isscalar)
p.addParameter('fieldSizeDegrees',30,@isscalar)
p.addParameter('pupilDiameterMm',2,@isscalar)
p.addParameter('nLEDsToKeep',8,@isscalar)
p.addParameter('minLEDspacing',20,@isscalar)
p.addParameter('weightedBackgroundPrimaries',false,@islogical)
p.addParameter('filterAdjacentPrimariesFlag',true,@islogical)
p.addParameter('filterMaxSlopeParam',1/5,@isscalar)
p.addParameter('primariesToKeepBest',[1 3 7 10 12 13 17 18],@isvector)
p.addParameter('filterCenterWavelengthsBest',[],@isvector) 
p.addParameter('nTests',inf,@isscalar)
p.addParameter('stepSizeDiffContrastSearch',0.025,@isscalar)
p.addParameter('shrinkFactorThresh',0.5,@isscalar)
p.addParameter('x0PrimaryChoice','background',@isscalar)
p.addParameter('verbose',true,@islogical)
p.addParameter('makePlots',true,@islogical)
p.parse(varargin{:});

% Set some constants
whichModel = 'human';
whichPrimaries = 'prizmatix';
maxPowerDiff = 10000; % No smoothness constraint enforced for the LED primaries
curDir = pwd;

% Load the table of LED primaries
spdTablePath = fullfile(fileparts(fileparts(mfilename('fullpath'))),'data',p.Results.ledSPDFileName);
spdTableFull = readtable(spdTablePath);

% Load the table of total power (in milliWatts) for each LED
powerTablePath = fullfile(fileparts(fileparts(mfilename('fullpath'))),'data',p.Results.ledTotalPowerFileName);
powerTableFull = readtable(powerTablePath);

% Save the list of names of the LEDs
totalLEDs = size(spdTableFull,2)-1;
LEDnames = spdTableFull.Properties.VariableNames(2:end);

% Derive the wavelength support
wavelengthSupport = spdTableFull.Wavelength;
S = [wavelengthSupport(1), wavelengthSupport(2)-wavelengthSupport(1), length(wavelengthSupport)];

% Scale the SPDs to reflect absolute power, and record the peak wavelength
% for each LED
for ii=1:totalLEDs
    thisSPD = cell2mat(table2cell(spdTableFull(:,ii+1)));
    thisName = LEDnames(ii);
    totalPowerMw = powerTableFull.(thisName{1});

    % We have some knowledge of the area of the emitting surface of the
    % LED. We get that number and adjust the power by the multiple of
    % square mm.
    switch thisName{1}(end-1:end)
        case 'EP'
            surfaceArea = 2*2;
        case 'SR'
            surfaceArea = 1.2*1.5;
        case '21' % The "LA21"
            surfaceArea = 2*1;
        otherwise
            error('Need the surface area for this LED')
    end

    % Apply the adjustment
    thisSPD = thisSPD .* ( (totalPowerMw*surfaceArea ) / (S(2) * sum(thisSPD)) );
    thisSPD(thisSPD<0)=0;
    spdTableFull(:,ii+1) = table(thisSPD);
    [~,idx]=max(thisSPD);
    LEDpeakWavelength(ii) = wavelengthSupport(idx);

end

LEDpower = cell2mat(table2cell(powerTableFull));


%% Get the photoreceptors
% Define photoreceptor classes that we'll consider.
% ReceptorIsolate has a few more built-ins than these.
photoreceptorClasses = {...
    'LConeTabulatedAbsorbance2Deg', 'MConeTabulatedAbsorbance2Deg', 'SConeTabulatedAbsorbance2Deg',...
    'LConeTabulatedAbsorbance10Deg', 'MConeTabulatedAbsorbance10Deg', 'SConeTabulatedAbsorbance10Deg',...
    'Melanopsin'};

photoreceptorClassNames = {'L_2deg','M_2deg','S_2deg','L_10deg','M_10deg','S_10deg','Mel'};

% Make sensitivities.  The wrapper routine is GetHumanPhotoreceptorSS,
% which is in the ContrastSplatter directory.  Each row of the matrix
% T_receptors provides the spectral sensitivity of the photoreceptor class
% in the corresponding entry of the cell array photoreceptorClasses.
%
% The last two arguments are the oxygenation fraction and the vessel
% thickness. We set them to be empty here.
oxygenationFraction = [];
vesselThickness = [];
fractionBleached = [];
T_receptors = GetHumanPhotoreceptorSS(S, photoreceptorClasses, p.Results.fieldSizeDegrees, p.Results.observerAgeInYears, p.Results.pupilDiameterMm, [], fractionBleached, oxygenationFraction, vesselThickness);


%% Define the receptor sets to isolate
% I consider the following modulations:
%   LMS -   Equal contrast on the peripheral cones, silencing Mel, as
%           this modulation would mostly be used in conjunction with
%           light flux and mel stimuli
%   LminusM - An L-M modulation that has equal contrast with eccentricity.
%           Ignore mel.
%   S -     An S modulation that has equal contrast with eccentricity.
%           Ignore mel.
%   Mel -   Mel directed, silencing peripheral but not central cones. It is
%           very hard to get any contrast on Mel while silencing both
%           central and peripheral cones. This stimulus would be used in
%           concert with occlusion of the macular region of the stimulus.
%   SnoMel- S modulation in the periphery that silences melanopsin.

whichDirectionSet = {'LMS','LminusM','S','Mel','SnoMel'};
whichReceptorsToTargetSet = {[4 5 6],[1 2 4 5],[3 6],[7],[6]};
whichReceptorsToIgnoreSet = {[1 2 3],[7],[7],[1 2 3],[1 2 3]};
whichReceptorsToMinimizeSet = {[],[],[],[],[]}; % This can be left empty. Any receptor that is neither targeted nor ignored will be silenced
desiredContrastSet = {repmat(0.5,1,3),[0.12 -0.12 0.12 -0.12],[0.7 0.7],0.6,0.65};
minAcceptableContrastSets = {...
    {[1,2,3]},...
    {[1,2],[3,4]},...
    {[1,2]},...
    {},...
    {},...
    };
minAcceptableContrastDiffSet = [0.015,0.005,0.025,0,0];
backgroundSearchFlag = [true,false,false,true,true];
whichDirectionsToScore = [1 4]; % Only these influence the metric

% whichDirectionSet = {'Mel'};
% whichReceptorsToTargetSet = {[7]};
% whichReceptorsToIgnoreSet = {[1 2 3]};
% whichReceptorsToMinimizeSet = {[]}; % This can be left empty. Any receptor that is neither targeted nor ignored will be silenced
% desiredContrastSet = {0.6};
% minAcceptableContrastSets = {...
%     {},...
%     };
% minAcceptableContrastDiffSet = [0];
% backgroundSearchFlag = [true];
% whichDirectionsToScore = [1]; % Only these influence the metric


%% Define the filter form
% Adjacent LEDs are subject to filtering by dichroic mirrors that direct
% the light. Generate here the form of that filter. The maximum slope of
% the logit function is set in the varargin.
logitFunc = @(x,x0) 1./(1+exp(-p.Results.filterMaxSlopeParam.*(x-x0)));


% Partition the LEDs into sets
if p.Results.nTests == 1
    nTests = 1;
    partitionSets = p.Results.primariesToKeepBest;
else
    partitionSets = nchoosek(1:totalLEDs,p.Results.nLEDsToKeep);

    % Loop through the partitions and mark the bad ones
    goodPatitions = ones(size(partitionSets,1),1);
    for ii=1:size(partitionSets,1)
        % Filter the partition sets to remove those that have LEDs that are
        % too close together
        if min(diff(LEDpeakWavelength(squeeze(partitionSets(ii,:))))) <= p.Results.minLEDspacing
            goodPatitions(ii)=0;
        end
    end

    % Remove the badness
    partitionSets = partitionSets(find(goodPatitions),:);

    % Randomize the order of the sets to search
    partitionSets = partitionSets(randperm(size(partitionSets,1)),:);
    nTests = min([p.Results.nTests,size(partitionSets,1)]);
end

% Alert the user
if p.Results.verbose
    tic
    fprintf(['Searching over %d LED partitions. Started ' char(datetime('now')) '\n'],nTests);
    fprintf('| 0                      50                   100%% |\n');
    fprintf('.\n');
end

% Loop over the tests
parfor dd = 1:nTests

    % Update progress
    if p.Results.verbose
        if mod(dd,round(nTests/50))==0
            fprintf('\b.\n');
        end
    end

    % Pick a random subset of the available LEDs to use as primaries
    primariesToKeep = partitionSets(dd,:);
    primariesToKeepNames = LEDnames(primariesToKeep);

    % Keep this part of the SPD table
    spdTable = spdTableFull(:,[1 primariesToKeep+1]);

    % Clear the resultSet variable and store a few of the variables used in
    % the computation
    resultSet = [];
    resultSet.primariesToKeepIdx = primariesToKeep;
    resultSet.primariesToKeepNames = primariesToKeepNames;
    resultSet.photoreceptorClassNames = photoreceptorClassNames;
    resultSet.T_receptors = T_receptors;
    resultSet.whichDirectionSet = whichDirectionSet;
    resultSet.whichReceptorsToTargetSet = whichReceptorsToTargetSet;
    resultSet.whichReceptorsToIgnoreSet = whichReceptorsToIgnoreSet;
    resultSet.whichReceptorsToMinimizeSet = whichReceptorsToMinimizeSet;
    resultSet.desiredContrastSet = desiredContrastSet;
    resultSet.minAcceptableContrastSets = minAcceptableContrastSets;
    resultSet.minAcceptableContrastDiffSet = minAcceptableContrastDiffSet;
    resultSet.backgroundSearchFlag = backgroundSearchFlag;

    % Derive the primaries from the SPD table
    B_primary = table2array(spdTable(:,2:end));
    nPrimaries = size(B_primary,2);

    % Store the primaries before filtering by the dichroic mirrors
    resultSet.B_primaryPreFilter = B_primary;

    % The primaries are arranged in a device that channels the light with
    % dichroic mirrors. This has the effect of filtering SPD of adjacent
    % primaries. Apply this here if requested.
    if p.Results.filterAdjacentPrimariesFlag
        filterCenterWavelengths = zeros(nPrimaries-1,1);
        for ii=1:nPrimaries-1

            % Find the midpoint wavelength between two adjacent LEDs, or
            % use the specified value in filterCentersNmBest
            if ~isempty(p.Results.filterCenterWavelengthsBest)
                filterCenterWavelengths(ii) = p.Results.filterCenterWavelengthsBest(ii);
                [~, filterCenterIdx] = min(abs(wavelengthSupport-filterCenterWavelengths(ii)));
            else
                primaryDiff = B_primary(:,ii)-B_primary(:,ii+1);
                [~,idx1]=max(primaryDiff);
                [~,idx2]=min(primaryDiff);
                [~,idx3]=min(abs(primaryDiff(idx1:idx2)));
                filterCenterIdx = idx1+idx3;
                filterCenterWavelengths(ii)=wavelengthSupport(filterCenterIdx);
            end

            % Make the filter
            filterTransmitance = logitFunc(1:length(wavelengthSupport),filterCenterIdx);

            % Apply the filter to the two primaries
            B_primary(:,ii) = B_primary(:,ii) .* (1-filterTransmitance)';
            B_primary(:,ii+1) = B_primary(:,ii+1) .* filterTransmitance';

        end
    end

    % Save the filter centers
    resultSet.filterCenterWavelength = filterCenterWavelengths;

    % Set up a zero ambient
    ambientSpd = zeros(S(3),1);

    % Add these to the resultSet
    resultSet.B_primary = B_primary;
    resultSet.ambientSpd = ambientSpd;

    % Loop over the set of directions for which we will generate
    % modulations
    for ss = 1:length(whichDirectionSet)

        % Extract values from the cell arrays
        whichDirection = whichDirectionSet{ss};
        whichReceptorsToTarget = whichReceptorsToTargetSet{ss};
        whichReceptorsToIgnore = whichReceptorsToIgnoreSet{ss};
        whichReceptorsToMinimize = whichReceptorsToMinimizeSet{ss};
        minAcceptableContrast = minAcceptableContrastSets{ss};
        minAcceptableContrastDiff = minAcceptableContrastDiffSet(ss);
        desiredContrast = desiredContrastSet{ss};

        % Don't pin any primaries.
        whichPrimariesToPin = [];

        % Set background
        if p.Results.weightedBackgroundPrimaries
            % Create a background that inversely weights the LEDs by their
            % total power
            j=LEDpower(primariesToKeep); j=j/max(j); j=j-mean(j); j=j/2;
            backgroundPrimary = (0.5-j)';
        else
            backgroundPrimary = repmat(0.5,nPrimaries,1);
        end

        % Decide upon an x0Primary to start the search
        switch p.Results.x0PrimaryChoice
            case 'background'
                x0Primary = backgroundPrimary;
            case 'ones'
                x0Primary = ones(size(backgroundPrimary));
            case 'random'
                x0Primary = rand(size(backgroundPrimary));
        end

        % Anonymous function that perfoms a modPrimarySearch for a
        % particular background defined by backgroundPrimary and x0
        myModPrimary = @(xBackPrimary) modPrimarySearch(...
            B_primary,xBackPrimary,x0Primary,ambientSpd,T_receptors,...
            whichReceptorsToTarget,whichReceptorsToIgnore,...
            whichReceptorsToMinimize,whichPrimariesToPin,...
            p.Results.primaryHeadRoom,maxPowerDiff,desiredContrast,...
            minAcceptableContrast,minAcceptableContrastDiff,...
            p.Results.verbose,p.Results.stepSizeDiffContrastSearch,...
            p.Results.shrinkFactorThresh);

        % Obtain the modulationPrimary for this background
        modulationPrimary = myModPrimary(backgroundPrimary);

        % Obtain the isomerization rate for the receptors by the background
        backgroundReceptors = T_receptors*(B_primary*backgroundPrimary + ambientSpd);

        % Store the background properties
        resultSet.(whichDirection).background.primary = backgroundPrimary;
        resultSet.(whichDirection).background.spd = B_primary*backgroundPrimary;
        resultSet.(whichDirection).background.wavelengthsNm = SToWls(S);

        % Store the modulation primaries
        resultSet.(whichDirection).modulationPrimary = modulationPrimary;

        % Calculate and store the positive and negative receptor contrast
        modulationReceptors = T_receptors*B_primary*(modulationPrimary - backgroundPrimary);
        contrastReceptors = modulationReceptors ./ backgroundReceptors;
        resultSet.(whichDirection).positiveReceptorContrast = contrastReceptors;

        modulationReceptors = T_receptors*B_primary*(-(modulationPrimary - backgroundPrimary));
        contrastReceptors = modulationReceptors ./ backgroundReceptors;
        resultSet.(whichDirection).negativeReceptorContrast = contrastReceptors;

        % Calculate and store the spectra
        resultSet.(whichDirection).positiveModulationSPD = B_primary*modulationPrimary;
        resultSet.(whichDirection).negativeModulationSPD = B_primary*(backgroundPrimary-(modulationPrimary - backgroundPrimary));
        resultSet.(whichDirection).wavelengthsNm = SToWls(S);

    end

    % Place the resultSet in the outcomes cell array
    outcomes{dd} = resultSet;

end

% alert the user that we are done with the search loop
if p.Results.verbose
    toc
    fprintf('\n');
end

% Obtain the set of contrasts for the modulations
for ss=1:length(whichDirectionSet)
    whichDirection = whichDirectionSet{ss};
    contrasts(ss,:) = cellfun(@(x) x.(whichDirection).positiveReceptorContrast(whichReceptorsToTargetSet{ss}(1)), outcomes);
end

% Normalize each contrast vector by the desired target contrast
contrasts = contrasts./cellfun(@(x) x(1),desiredContrastSet)';

% Only pay attention to those contrasts that we are asked to score
contrasts = contrasts(whichDirectionsToScore,:);

% Find the best outcome
[~,idxBestOutcome]=min(max((1-contrasts)));
resultSet = outcomes{idxBestOutcome};

% Create the save dir
if ~isempty(p.Results.saveDir)
    if ~isfolder(p.Results.saveDir)
        mkdir(p.Results.saveDir);
    end
end

% Save the results file
cd(p.Results.saveDir);
save('resultSet.mat','resultSet');

% Loop through the directions and save figures
if p.Results.makePlots
for ss = 1:length(whichDirectionSet)

    % Extract values from the cell arrays
    whichDirection = whichDirectionSet{ss};

    % Create a figure with an appropriate title
    fighandle = figure('Name',sprintf([whichDirection ': contrast = %2.2f'],resultSet.(whichDirection).positiveReceptorContrast(whichReceptorsToTargetSet{ss}(1))));

    % Modulation spectra
    subplot(1,2,1)
    hold on
    plot(resultSet.(whichDirection).wavelengthsNm,resultSet.(whichDirection).positiveModulationSPD,'k','LineWidth',2);
    plot(resultSet.(whichDirection).wavelengthsNm,resultSet.(whichDirection).negativeModulationSPD,'r','LineWidth',2);
    plot(resultSet.(whichDirection).background.wavelengthsNm,resultSet.(whichDirection).background.spd,'Color',[0.5 0.5 0.5],'LineWidth',2);
    title(sprintf('Modulation spectra [%2.2f]',resultSet.(whichDirection).positiveReceptorContrast(whichReceptorsToTargetSet{ss}(1))));
    xlim([300 800]);
    xlabel('Wavelength');
    ylabel('Power');
    legend({'Positive', 'Negative', 'Background'},'Location','NorthEast');

    % Primaries
    subplot(1,2,2)
    c = categorical(resultSet.primariesToKeepNames);
    hold on
    plot(c,resultSet.(whichDirection).modulationPrimary,'*k');
    plot(c,resultSet.(whichDirection).background.primary+(-(resultSet.(whichDirection).modulationPrimary-resultSet.(whichDirection).background.primary)),'*r');
    plot(c,resultSet.(whichDirection).background.primary,'-*','Color',[0.5 0.5 0.5]);
    set(gca,'TickLabelInterpreter','none');
    title('Primary settings');
    ylim([0 1]);
    xlabel('Primary');
    ylabel('Setting');

    % Save the figure
    saveas(fighandle,sprintf('%s_%s_%s_PrimariesAndSPD.pdf',whichModel,whichPrimaries,whichDirection),'pdf');

end
end

% Return to the directory from whence we started
cd(curDir);

end
