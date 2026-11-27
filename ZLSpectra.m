function ZLSpectra
% ZLSpectra - Modular diffuse reflectance spectroscopy workflow
%
% Module 1: established mineral spectral proxies implemented within this file
%   (Fe oxides, gypsum, carbonate, kaolinite, illite, chlorite, 2:1 clays and gibbsite).
% Module 2: mineral-independent configurable spectral processing and feature
%   extraction presented as one processing framework.
%   panel. Wavelength range, transformation, baseline/scatter correction,
%   normalization, smoothing and derivative steps can be combined freely.
%
% General method sources represented in the configurable processing module:
%   Piccini et al. (2024): commonly used soil Vis-NIR preprocessing,
%       including SG, continuum removal, SNV and spectral derivatives.
%   Yan et al. (2025): cross-disciplinary preprocessing framework covering
%       baseline/scatter correction, normalization, filtering and derivatives.
%   Clark & Roush (1984): apparent absorbance and continuum removal.
%   Barnes et al. (1989): standard normal variate transformation.
%   Savitzky & Golay (1964): local polynomial smoothing/differentiation.
%
% The generic tools do not convert a spectral metric into mineral content
% unless the user supplies and validates an external calibration.

close all; clc;

moduleOptions = { ...
    'Module 1 - Established Mineral Spectral Proxies', ...
    'Module 2 - Configurable spectral processing and feature extraction'};
[moduleIndex, selected] = listdlg( ...
    'PromptString', {'Select a ZLSpectra module:', ...
    ['Module 1 applies established mineral spectral proxies; ', ...
    'Module 2 provides configurable spectral processing.']}, ...
    'SelectionMode', 'single', 'ListString', moduleOptions, ...
    'InitialValue', 1, 'ListSize', [470 135], 'Name', 'ZLSpectra');
if ~selected, return; end

if moduleIndex == 1
    taskOptions = {'Mineral proxies','Derived proxy calculation'};
    [taskIndex, chosen] = listdlg('PromptString','Select a task:', ...
        'SelectionMode','single','ListString',taskOptions, ...
        'InitialValue',1,'ListSize',[430 110], ...
        'Name','Established Mineral Spectral Proxies');
    if ~chosen, return; end
    if taskIndex == 2
        [derivedIndex, chosen] = listdlg( ...
            'PromptString','Select a derived proxy:', ...
            'SelectionMode','single','ListString',{'RelHm+Gt'}, ...
            'InitialValue',1,'ListSize',[430 90], ...
            'Name','Derived Proxy Calculation');
        if ~chosen, return; end
        if derivedIndex == 1, runRelProxy(); end
        return;
    end
    proxyOptions = {'Hematite','Goethite','Gypsum','Calcium carbonate', ...
        'Kaolinite','Illite','Chlorite','2:1 clay minerals','Gibbsite'};
    [proxyIndex, chosen] = listdlg('PromptString','Select a target mineral:', ...
        'SelectionMode','single','ListString',proxyOptions, ...
        'InitialValue',1,'ListSize',[430 285],'Name','Mineral Proxies');
    if ~chosen, return; end
    runEstablishedMineralModule(proxyOptions{proxyIndex});
    return;
end

runConfigurableSpectralModule();
end

function runRelProxy()
% Zhang et al. (2021), Text S1, doi:10.1029/2021GL094687;
% original proxy: Zhang et al. (2018), doi:10.1002/2017JB014951.
% Normalize over one common population of valid paired samples.
try
    [mode, ok] = listdlg('PromptString','Select the intensity input layout:', ...
        'SelectionMode','single','ListString', ...
        {'Hematite and goethite in the same worksheet', ...
         'Separate worksheets or files for hematite and goethite'}, ...
        'ListSize',[490 100],'Name','RelHm+Gt: Input');
    if ~ok, return; end
    [hCells,hSource] = relReadInput('Select the hematite intensity table');
    if isempty(hCells), return; end
    [hID,hValue,hRows,ok] = relSelectColumns(hCells,'Hematite');
    if ~ok, return; end
    if mode == 1
        gCells = hCells; gSource = hSource;
    else
        [gCells,gSource] = relReadInput('Select the goethite intensity table');
        if isempty(gCells), return; end
    end
    [gID,gValue,gRows,ok] = relSelectColumns(gCells,'Goethite');
    if ~ok, return; end
    [matched,location] = ismember(hID,gID);
    valid = matched & isfinite(hValue) & hValue >= 0;
    valid(matched) = valid(matched) & isfinite(gValue(location(matched))) ...
        & gValue(location(matched)) >= 0;
    ids = hID(valid); H = hValue(valid); G = gValue(location(valid));
    if isempty(ids), error('No valid paired samples were found.'); end
    if sum(H) <= 0 || sum(G) <= 0
        error('Both mineral intensity sums must be positive.');
    end
    % Exact IDs are matched after whitespace trimming and numeric-ID normalization.
    n = numel(ids);
    answer = questdlg(sprintf(['Use all %d valid paired samples for normalization?\n' ...
        'Hematite records: %d; goethite records: %d.\n' ...
        'Missing, nonnumeric and negative intensities are excluded.\n' ...
        'REL is relative to this selected population.'],n,numel(hID),numel(gID)), ...
        'RelHm+Gt: Normalization','Calculate','Cancel','Calculate');
    if ~strcmp(answer,'Calculate'), return; end
    % Natural ordering for sample labels such as 2, 10 or sample2, sample10.
    [~,order] = sort(naturalRelKeys(ids));
    ids = ids(order); H = H(order); G = G(order);
    RelHm = n*H/sum(H); RelGt = n*G/sum(G);
    REL = RelHm + RelGt;
    result = table(ids,H,G,RelHm,RelGt,REL,'VariableNames', ...
        {'Sample_ID','I_Hm','I_Gt','Rel_Hm','Rel_Gt','Rel_Hm_Gt'});
    % Keep excluded source records inspectable, including unmatched IDs.
    excluded = cell(0,4);
    for k = 1:numel(hID)
        if ~valid(k)
            excluded(end+1,:) = {'Hematite',char(hID(k)),hRows(k), ...
                'Unmatched ID or invalid intensity in the pair'}; %#ok<AGROW>
        end
    end
    for k = 1:numel(gID)
        if ~ismember(gID(k),ids)
            excluded(end+1,:) = {'Goethite',char(gID(k)),gRows(k), ...
                'Unmatched ID or invalid intensity in the pair'}; %#ok<AGROW>
        end
    end
    [name,folder] = uiputfile('*.xlsx','Save RelHm+Gt results:', 'ZLSpectra_REL_Hm_Gt.xlsx');
    if isequal(name,0), return; end
    output = fullfile(folder,name);
    if strcmpi(output,hSource.File) || strcmpi(output,gSource.File)
        error('Choose an output file different from the input files.');
    end
    if isfile(output)
        error('The output file already exists. Choose a new filename to preserve previous results.');
    end
    writetable(result,output,'Sheet','REL');
    writecell({'Parameter','Value'; ...
        'Formula','n * (I_Hm / sum(I_Hm) + I_Gt / sum(I_Gt))'; ...
        'Population','All valid paired samples in the selected input tables'; ...
        'n',n;'Sum_I_Hm',sum(H);'Sum_I_Gt',sum(G); ...
        'Mean_I_Hm',mean(H);'Mean_I_Gt',mean(G); ...
        'Mean_REL',mean(REL);'Sum_REL',sum(REL); ...
        'Hematite_source',hSource.File;'Hematite_sheet',hSource.Sheet; ...
        'Goethite_source',gSource.File;'Goethite_sheet',gSource.Sheet; ...
        'Interpretation','Dimensionless relative abundance; not concentration or flux'; ...
        'Reference','Zhang et al. (2021), Text S1, doi:10.1029/2021GL094687'; ...
        'Original_reference','Zhang et al. (2018), doi:10.1002/2017JB014951'}, ...
        output,'Sheet','Calculation');
    writecell([{'Mineral','Sample_ID','Source_row','Reason'};excluded], ...
        output,'Sheet','Excluded');
    figure('Name','RelHm+Gt Calculation','Color','w');
    numericIDs = str2double(ids);
    if all(isfinite(numericIDs))
        plot(numericIDs,REL,'-o'); xlabel('Sample ID');
    else
        plot(1:n,REL,'-o'); xlabel('Sample order');
        tick = unique(round(linspace(1,n,min(n,20))));
        xticks(tick); xticklabels(ids(tick)); xtickangle(45);
    end
    ylabel('Rel_{Hm+Gt}'); grid on;
    title(sprintf('Rel_{Hm+Gt} (n = %d)',n));
    msgbox(sprintf('RelHm+Gt results saved to:\n%s',output), ...
        'RelHm+Gt: Complete','modal');
catch ME
    errordlg(ME.message,'RelHm+Gt Calculation');
end
end

function [cells,source] = relReadInput(prompt)
cells = {}; source = struct('File','','Sheet','');
[name,folder] = uigetfile({'*.xlsx;*.xls;*.csv;*.txt','Intensity tables'},prompt);
if isequal(name,0), return; end
source.File = fullfile(folder,name);
[~,~,extension] = fileparts(name);
if any(strcmpi(extension,{'.xlsx','.xls'}))
    sheets = sheetnames(source.File);
    [idx,ok] = listdlg('PromptString','Select the worksheet containing intensities:', ...
        'SelectionMode','single','ListString',cellstr(sheets),'Name','REL worksheet');
    if ~ok, return; end
    source.Sheet = char(sheets(idx));
    cells = readcell(source.File,'Sheet',source.Sheet);
else
    cells = readcell(source.File);
end
end

function [ids,values,sourceRows,ok] = relSelectColumns(cells,mineral)
ids = strings(0,1); values = []; sourceRows = []; ok = false;
% Locate common exported headers, while allowing explicit row/column mapping.
header = 1;
for r = 1:min(10,size(cells,1))
    row = string(cellfun(@relCellText,cells(r,:),'UniformOutput',false));
    if any(contains(lower(row),{'sample','序号','编号'}))
        header = r; break;
    end
end
answer = inputdlg('Header row number (data start on the following row):', ...
    [mineral ' input'],1,{num2str(header)});
if isempty(answer), return; end
header = str2double(answer{1});
if ~isscalar(header) || ~isfinite(header) || header < 1 || ...
        header ~= fix(header) || header >= size(cells,1)
    error('Invalid header row.');
end
labels = cell(1,size(cells,2));
for c = 1:size(cells,2)
    labels{c} = sprintf('Column %d: %s',c,relCellText(cells{header,c}));
end
[idCol,chosen] = listdlg('PromptString',[mineral ': select the sample ID column'], ...
    'SelectionMode','single','ListString',labels,'ListSize',[500 230]);
if ~chosen, return; end
[valueCol,chosen] = listdlg('PromptString', ...
    [mineral ': select intensity (peak y minus valley y), not wavelength'], ...
    'SelectionMode','single','ListString',labels,'ListSize',[500 230]);
if ~chosen, return; end
if idCol == valueCol, error('Sample ID and intensity must use different columns.'); end
for r = header+1:size(cells,1)
    id = strtrim(relCellText(cells{r,idCol}));
    if isempty(id), continue; end
    number = str2double(id);
    if isfinite(number), id = sprintf('%.15g',number); end
    ids(end+1,1) = string(id); %#ok<AGROW>
    values(end+1,1) = str2double(relCellText(cells{r,valueCol})); %#ok<AGROW>
    sourceRows(end+1,1) = r; %#ok<AGROW>
end
if numel(unique(ids)) ~= numel(ids)
    error('%s input contains duplicate sample IDs. Resolve duplicates before calculating REL.',mineral);
end
ok = true;
end

function textValue = relCellText(value)
textValue = '';
if isempty(value), return; end
if (isnumeric(value) || islogical(value)) && isscalar(value)
    if isfinite(double(value)), textValue = sprintf('%.17g',double(value)); end
elseif ischar(value)
    textValue = value;
elseif isstring(value) && isscalar(value) && ~ismissing(value)
    textValue = char(value);
end
end

function keys = naturalRelKeys(ids)
keys = cellstr(lower(ids));
for k = 1:numel(keys)
    [parts,startIndex,endIndex] = regexp(keys{k},'\d+','match','start','end');
    for j = numel(parts):-1:1
        keys{k} = [keys{k}(1:startIndex(j)-1), ...
            sprintf('%020.0f',str2double(parts{j})),keys{k}(endIndex(j)+1:end)];
    end
end
end

function runConfigurableSpectralModule()
uiwait(msgbox('Select the folder containing the spectra.', ...
    'Configurable spectral processing: Input folder', 'modal'));
inputFolder = uigetdir(pwd, 'Select the folder containing the spectra');
if isequal(inputFolder, 0), return; end

samples = collectAllSamples(inputFolder, '');
if isempty(samples), error('No valid spectra were found in the selected folder.'); end
samples = sortSamplesByNumber(samples);

config = askProcessingConfiguration(samples);
if isempty(config), return; end
processAndExport(samples, config, inputFolder);
end

function config = askProcessingConfiguration(samples)
% Configurable analytical framework with an immediate before/after preview.
config = [];
allWavelengths = vertcat(samples.Wavelength);
defaultRange = [floor(min(allWavelengths)) ceil(max(allWavelengths))];
transformOptions = {'Reflectance R', ...
    'Kubelka-Munk F(R) = (1-R)^2/(2R)', ...
    'Apparent absorbance A = -ln(R)'};
baselineOptions = {'None','Linear detrend','Continuum removal Y/Yc'};
scatterOptions = {'None','Standard normal variate (SNV)'};
normalizationOptions = {'None','Min-max (0-1)','Vector L2 norm', ...
    'Area normalization','Mean centering'};
smoothingOptions = {'None','Savitzky-Golay','Moving mean', ...
    'Moving median','Gaussian weighted'};

f = uifigure('Name','ZLSpectra Configurable Spectral Processing and Feature Extraction', ...
    'Position',[40 45 1450 850],'WindowStyle','modal');
main = uigridlayout(f,[2 2]);
main.RowHeight = {'1x',190}; main.ColumnWidth = {470,'1x'};

controlPanel = uipanel(main,'Title','1. Select processing operations', ...
    'FontWeight','bold','Scrollable','on');
controlPanel.Layout.Row = [1 2]; controlPanel.Layout.Column = 1;
c = uigridlayout(controlPanel,[19 2]);
c.RowHeight = repmat({30},1,19); c.ColumnWidth = {220,'1x'};

uilabel(c,'Text','Display start wavelength (nm)');
startField = uieditfield(c,'numeric','Value',defaultRange(1));
uilabel(c,'Text','Display end wavelength (nm)');
endField = uieditfield(c,'numeric','Value',defaultRange(2));
uilabel(c,'Text','Uniform grid interval (nm)');
gridField = uieditfield(c,'numeric','Value',1,'Limits',[0 Inf], ...
    'Tooltip','Enter 0 to retain native sampling.');
uilabel(c,'Text','Ordinate transformation');
transformDrop = uidropdown(c,'Items',transformOptions,'Value',transformOptions{1});
uilabel(c,'Text','Baseline / continuum');
baselineDrop = uidropdown(c,'Items',baselineOptions,'Value',baselineOptions{1});
uilabel(c,'Text','Left continuum start / end (nm)');
leftBox = uigridlayout(c,[1 2]); leftBox.Padding = 0;
leftStart = uieditfield(leftBox,'numeric','Value',defaultRange(1));
leftEnd = uieditfield(leftBox,'numeric','Value',defaultRange(1));
uilabel(c,'Text','Right continuum start / end (nm)');
rightBox = uigridlayout(c,[1 2]); rightBox.Padding = 0;
rightStart = uieditfield(rightBox,'numeric','Value',defaultRange(2));
rightEnd = uieditfield(rightBox,'numeric','Value',defaultRange(2));
uilabel(c,'Text','Scatter correction');
scatterDrop = uidropdown(c,'Items',scatterOptions,'Value',scatterOptions{1});
uilabel(c,'Text','Intensity normalization');
normalizationDrop = uidropdown(c,'Items',normalizationOptions,'Value',normalizationOptions{1});
uilabel(c,'Text','Smoothing method');
smoothingDrop = uidropdown(c,'Items',smoothingOptions,'Value',smoothingOptions{1});
uilabel(c,'Text','Smoothing window (odd points)');
smoothWindowField = uieditfield(c,'numeric','Value',5,'Limits',[1 Inf], ...
    'RoundFractionalValues','on');
uilabel(c,'Text','Smoothing polynomial order');
smoothOrderField = uieditfield(c,'numeric','Value',2,'Limits',[0 Inf], ...
    'RoundFractionalValues','on');
uilabel(c,'Text','First derivative');
firstCheck = uicheckbox(c,'Text','Apply','Value',false);
uilabel(c,'Text','Second derivative');
secondCheck = uicheckbox(c,'Text','Apply','Value',false, ...
    'Tooltip',['When both boxes are checked, ZLSpectra applies a first ', ...
    'derivative twice in sequence.']);
uilabel(c,'Text','Derivative SG window (odd points)');
derivativeWindowField = uieditfield(c,'numeric','Value',29,'Limits',[3 Inf], ...
    'RoundFractionalValues','on');
uilabel(c,'Text','Derivative polynomial order');
derivativeOrderField = uieditfield(c,'numeric','Value',2,'Limits',[1 Inf], ...
    'RoundFractionalValues','on');
previewButton = uibutton(c,'Text','Update preview','FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~) updatePreview(true));
acceptButton = uibutton(c,'Text','Use workflow and review samples', ...
    'FontWeight','bold','ButtonPushedFcn',@(~,~) acceptPanel());
cancelButton = uibutton(c,'Text','Cancel', ...
    'ButtonPushedFcn',@(~,~) cancelPanel());

previewPanel = uipanel(main,'Title','2. Preview using the first dataset', ...
    'FontWeight','bold');
previewPanel.Layout.Row = 1; previewPanel.Layout.Column = 2;
p = uigridlayout(previewPanel,[2 1]);
rawAx = uiaxes(p); processedAx = uiaxes(p);

workflowPanel = uipanel(main,'Title','3. Current workflow', ...
    'FontWeight','bold');
workflowPanel.Layout.Row = 2; workflowPanel.Layout.Column = 2;
w = uigridlayout(workflowPanel,[1 1]);
workflowText = uitextarea(w,'Editable','off');

% Every menu/parameter change immediately refreshes the first-sample preview.
startField.ValueChangedFcn = @(~,~) updatePreview(false);
endField.ValueChangedFcn = @(~,~) updatePreview(false);
gridField.ValueChangedFcn = @(~,~) updatePreview(false);
transformDrop.ValueChangedFcn = @(~,~) updatePreview(false);
baselineDrop.ValueChangedFcn = @(~,~) updatePreview(false);
leftStart.ValueChangedFcn = @(~,~) updatePreview(false);
leftEnd.ValueChangedFcn = @(~,~) updatePreview(false);
rightStart.ValueChangedFcn = @(~,~) updatePreview(false);
rightEnd.ValueChangedFcn = @(~,~) updatePreview(false);
scatterDrop.ValueChangedFcn = @(~,~) updatePreview(false);
normalizationDrop.ValueChangedFcn = @(~,~) updatePreview(false);
smoothingDrop.ValueChangedFcn = @(~,~) updatePreview(false);
smoothWindowField.ValueChangedFcn = @(~,~) updatePreview(false);
smoothOrderField.ValueChangedFcn = @(~,~) updatePreview(false);
firstCheck.ValueChangedFcn = @(~,~) updatePreview(false);
secondCheck.ValueChangedFcn = @(~,~) updatePreview(false);
derivativeWindowField.ValueChangedFcn = @(~,~) updatePreview(false);
derivativeOrderField.ValueChangedFcn = @(~,~) updatePreview(false);

f.CloseRequestFcn = @(~,~) cancelPanel();
updatePreview(false);
uiwait(f);

    function candidate = readPanel()
        analysisRange = [startField.Value endField.Value];
        if any(~isfinite(analysisRange)) || analysisRange(2) <= analysisRange(1)
            error('The end wavelength must be greater than the start wavelength.');
        end
        if gridField.Value < 0, error('Grid interval cannot be negative.'); end
        if ~strcmp(smoothingDrop.Value,'None')
            validateOddWindow(smoothWindowField.Value,smoothOrderField.Value, ...
                strcmp(smoothingDrop.Value,'Savitzky-Golay'));
        end
        firstSelected = firstCheck.Value;
        secondSelected = secondCheck.Value;
        if secondSelected, derivativeOrder = 2;
        elseif firstSelected, derivativeOrder = 1;
        else, derivativeOrder = 0;
        end
        if derivativeOrder > 0
            validateOddWindow(derivativeWindowField.Value, ...
                derivativeOrderField.Value,true);
            if derivativeOrderField.Value < derivativeOrder && ~firstSelected
                error('Derivative polynomial order must be at least the derivative order.');
            end
        end
        continuumRanges = [leftStart.Value leftEnd.Value rightStart.Value rightEnd.Value];
        if strcmp(baselineDrop.Value,'Continuum removal Y/Yc') && ...
                (continuumRanges(1)>continuumRanges(2) || ...
                continuumRanges(3)>continuumRanges(4) || ...
                continuumRanges(2)>=continuumRanges(3))
            error('Continuum intervals must be ordered and non-overlapping.');
        end
        candidate.AnalysisRange = analysisRange;
        candidate.GridStep = gridField.Value;
        candidate.Transform = find(strcmp(transformOptions,transformDrop.Value),1);
        candidate.TransformName = transformDrop.Value;
        candidate.Baseline = find(strcmp(baselineOptions,baselineDrop.Value),1);
        candidate.BaselineName = baselineDrop.Value;
        candidate.ContinuumRanges = continuumRanges;
        candidate.Scatter = find(strcmp(scatterOptions,scatterDrop.Value),1);
        candidate.ScatterName = scatterDrop.Value;
        candidate.Normalization = find(strcmp(normalizationOptions,normalizationDrop.Value),1);
        candidate.NormalizationName = normalizationDrop.Value;
        candidate.Smoothing = find(strcmp(smoothingOptions,smoothingDrop.Value),1);
        candidate.SmoothingName = smoothingDrop.Value;
        candidate.SmoothWindow = smoothWindowField.Value;
        candidate.SmoothPolynomialOrder = smoothOrderField.Value;
        candidate.DerivativeOrder = derivativeOrder;
        candidate.FirstDerivativeSelected = firstSelected;
        candidate.SecondDerivativeSelected = secondSelected;
        candidate.SequentialDerivative = firstSelected && secondSelected;
        candidate.DerivativeWindow = derivativeWindowField.Value;
        candidate.DerivativePolynomialOrder = derivativeOrderField.Value;
    end

    function updatePreview(showAlert)
        try
            candidate = readPanel();
            original = rawSpectrum(samples(1),candidate.AnalysisRange);
            processed = applyWorkflow(samples(1),candidate);
            plot(rawAx,original.Wavelength,original.Value,'k-','LineWidth',1.1);
            grid(rawAx,'on'); xlabel(rawAx,'Wavelength (nm)');
            ylabel(rawAx,'Reflectance R');
            title(rawAx,['Original: ',samples(1).Name],'Interpreter','none');
            plot(processedAx,processed.Wavelength,processed.Value, ...
                'b-','LineWidth',1.1);
            grid(processedAx,'on'); xlabel(processedAx,'Wavelength (nm)');
            ylabel(processedAx,ordinateLabel(candidate));
            title(processedAx,'Processed preview');
            workflowText.Value = workflowDescription(candidate);
        catch ME
            if showAlert, uialert(f,ME.message,'Preview unavailable'); end
        end
    end

    function acceptPanel()
        try
            config = readPanel();
            applyWorkflow(samples(1),config);
        catch ME
            uialert(f,ME.message,'Invalid workflow'); return;
        end
        uiresume(f); delete(f);
    end
    function cancelPanel()
        config = [];
        if isvalid(f), uiresume(f); delete(f); end
    end
end

function processAndExport(samples, config, inputFolder)
% Review samples one at a time. Two optional clicks are stored per sample.
[outputName,outputDir] = uiputfile('*.xlsx','Save spectral-analysis results:', ...
    fullfile(inputFolder,'ZLSpectra_Configurable_Spectral_Processing.xlsx'));
if isequal(outputName,0), return; end
outputFile = fullfile(outputDir,outputName);

results = cell(numel(samples),1); valid = false(numel(samples),1);
for k = 1:numel(samples)
    try, results{k} = applyWorkflow(samples(k),config); valid(k) = true;
    catch ME, warning('Skipping %s: %s',samples(k).Name,ME.message);
    end
end
samples = samples(valid); results = results(valid);
if isempty(samples), error('No spectrum could be processed.'); end

selection = nan(numel(samples),6); % x1,y1,x2,y2,deltaY,deltaX
current = 1; finished = false;
fig = figure('Name','ZLSpectra Spectral Feature Review','Color','w', ...
    'Position',[80 55 1350 820],'NumberTitle','off');
rawAx = axes(fig,'Position',[.07 .57 .68 .35]);
processedAx = axes(fig,'Position',[.07 .13 .68 .35]);
info = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[.78 .60 .20 .31],'HorizontalAlignment','left', ...
    'BackgroundColor','w','FontSize',10);
uicontrol(fig,'Style','pushbutton','String','Previous','Units','normalized', ...
    'Position',[.78 .49 .09 .055],'Callback',@(~,~) moveSample(-1));
uicontrol(fig,'Style','pushbutton','String','Next','Units','normalized', ...
    'Position',[.89 .49 .09 .055],'Callback',@(~,~) moveSample(1));
uicontrol(fig,'Style','pushbutton','String','Select two points','Units','normalized', ...
    'Position',[.78 .40 .20 .06],'FontWeight','bold', ...
    'Callback',@(~,~) selectTwoPoints());
uicontrol(fig,'Style','pushbutton','String','Clear selected points','Units','normalized', ...
    'Position',[.78 .32 .20 .055],'Callback',@(~,~) clearPoints());
uicontrol(fig,'Style','pushbutton','String','Finish and export','Units','normalized', ...
    'Position',[.78 .20 .20 .075],'FontWeight','bold', ...
    'Callback',@(~,~) finishReview());
uicontrol(fig,'Style','pushbutton','String','Cancel','Units','normalized', ...
    'Position',[.78 .12 .20 .055],'Callback',@(~,~) cancelReview());
fig.CloseRequestFcn = @(~,~) cancelReview();
drawCurrent(); uiwait(fig);
if ~finished, return; end

longRows = cell(0,3);
for k = 1:numel(samples)
    n = numel(results{k}.Wavelength);
    longRows(end+1:end+n,:) = [repmat({samples(k).Name},n,1), ...
        num2cell(results{k}.Wavelength),num2cell(results{k}.Value)]; %#ok<AGROW>
end
writetable(cell2table(longRows,'VariableNames', ...
    {'Sample','Wavelength_nm','Processed_value'}),outputFile,'Sheet','Processed_long');
selectionTable = table({samples.Name}.',selection(:,1),selection(:,2), ...
    selection(:,3),selection(:,4),selection(:,5),selection(:,6), ...
    'VariableNames',{'Sample','Point1_nm','Point1_value','Point2_nm', ...
    'Point2_value','Point2_minus_Point1','Wavelength_separation_nm'});
writetable(selectionTable,outputFile,'Sheet','Selected_points');
writeConfiguration(outputFile,config);
msgbox(sprintf('Results saved to:\n%s',outputFile), ...
    'ZLSpectra Spectral Processing','modal');

    function drawCurrent()
        original = rawSpectrum(samples(current),config.AnalysisRange);
        cla(rawAx); plot(rawAx,original.Wavelength,original.Value,'k-','LineWidth',1.1);
        grid(rawAx,'on'); xlabel(rawAx,'Wavelength (nm)'); ylabel(rawAx,'Reflectance R');
        title(rawAx,sprintf('Original | %d/%d | %s',current,numel(samples), ...
            samples(current).Name),'Interpreter','none');
        cla(processedAx); plot(processedAx,results{current}.Wavelength, ...
            results{current}.Value,'b-','LineWidth',1.15); hold(processedAx,'on');
        if all(isfinite(selection(current,1:4)))
            plot(processedAx,selection(current,[1 3]),selection(current,[2 4]), ...
                'ro','MarkerFaceColor','r','MarkerSize',7);
        end
        grid(processedAx,'on'); xlabel(processedAx,'Wavelength (nm)');
        ylabel(processedAx,ordinateLabel(config)); title(processedAx,'Processed spectrum');
        info.String = sprintf(['CURRENT WORKFLOW\n%s\n\nSELECTED POINTS\n', ...
            'P1: %.6g nm, %.6g\nP2: %.6g nm, %.6g\nDelta Y: %.6g'], ...
            strjoin(workflowDescription(config),'\n'),selection(current,1), ...
            selection(current,2),selection(current,3),selection(current,4), ...
            selection(current,5));
    end
    function moveSample(direction)
        current = min(max(current+direction,1),numel(samples)); drawCurrent();
    end
    function selectTwoPoints()
        axes(processedAx); %#ok<LAXES>
        [clickedX,~] = ginput(2);
        if numel(clickedX)<2, return; end
        [~,i1] = min(abs(results{current}.Wavelength-clickedX(1)));
        [~,i2] = min(abs(results{current}.Wavelength-clickedX(2)));
        x1 = results{current}.Wavelength(i1); y1 = results{current}.Value(i1);
        x2 = results{current}.Wavelength(i2); y2 = results{current}.Value(i2);
        selection(current,:) = [x1 y1 x2 y2 y2-y1 x2-x1]; drawCurrent();
    end
    function clearPoints()
        selection(current,:) = nan; drawCurrent();
    end
    function finishReview()
        finished = true; uiresume(fig); delete(fig);
    end
    function cancelReview()
        finished = false;
        if isvalid(fig), uiresume(fig); delete(fig); end
    end
end

function result = applyWorkflow(sample, config)
x = sample.Wavelength(:); r = sample.Reflectance(:);
valid = isfinite(x) & isfinite(r); x = x(valid); r = r(valid);
[x, order] = sort(x); r = r(order);
[x, ~, group] = unique(x); r = accumarray(group, r, [], @mean);
mask = x >= config.AnalysisRange(1) & x <= config.AnalysisRange(2);
x = x(mask); r = r(mask);
if numel(x) < 7, error('Too few observations in the analysis range.'); end
if max(r) > 1.5 && max(r) <= 100.5, r = r/100; end
if any(r <= 0) || any(r > 1.05)
    error('Reflectance must be in 0-1 or 0-100 and must be positive.');
end

needsUniform = config.GridStep > 0 || config.Smoothing == 2 || ...
    config.DerivativeOrder > 0;
if needsUniform
    if config.GridStep > 0, step = config.GridStep; else, step = median(diff(x)); end
    xGrid = (ceil(x(1)/step)*step:step:floor(x(end)/step)*step).';
    r = interp1(x, r, xGrid, 'linear'); x = xGrid;
else
    step = median(diff(x));
end

switch config.Transform
    case 1
        y = r;
    case 2
        y = (1-r).^2./(2*r);
    case 3
        y = -log(r);
end

switch config.Baseline
    case 1
        % No baseline operation.
    case 2
        y = detrend(y, 'linear');
    case 3
        c = config.ContinuumRanges;
        left = x >= c(1) & x <= c(2); right = x >= c(3) & x <= c(4);
        if ~any(left) || ~any(right)
            error('Continuum interval does not contain data points.');
        end
        xa = mean(x(left)); ya = mean(y(left));
        xb = mean(x(right)); yb = mean(y(right));
        continuum = ya + (yb-ya)*(x-xa)/(xb-xa);
        if any(abs(continuum) < eps)
            error('The fitted continuum contains zero values.');
        end
        y = y./continuum;
end

if config.Scatter == 2
    scale = std(y, 0, 'omitnan');
    if ~isfinite(scale) || scale <= eps
        error('SNV cannot be applied to a constant spectrum.');
    end
    y = (y-mean(y,'omitnan'))/scale;
end

switch config.Normalization
    case 1
        % No normalization.
    case 2
        span = max(y)-min(y);
        if span <= eps, error('Min-max normalization requires nonconstant data.'); end
        y = (y-min(y))/span;
    case 3
        scale = norm(y,2);
        if scale <= eps, error('L2 normalization requires nonzero data.'); end
        y = y/scale;
    case 4
        scale = trapz(x,abs(y));
        if abs(scale) <= eps, error('Area normalization requires nonzero area.'); end
        y = y/scale;
    case 5
        y = y-mean(y,'omitnan');
end

if config.Smoothing == 2
    y = applySg(y, config.SmoothWindow, config.SmoothPolynomialOrder, 0, step);
elseif config.Smoothing == 3
    y = movmean(y, config.SmoothWindow, 'Endpoints', 'shrink');
elseif config.Smoothing == 4
    y = movmedian(y, config.SmoothWindow, 'Endpoints', 'shrink');
elseif config.Smoothing == 5
    y = gaussianSmooth(y, config.SmoothWindow);
end
if config.SequentialDerivative
    y = applySg(y, config.DerivativeWindow, config.DerivativePolynomialOrder, ...
        1, step);
    y = applySg(y, config.DerivativeWindow, config.DerivativePolynomialOrder, ...
        1, step);
elseif config.DerivativeOrder > 0
    y = applySg(y, config.DerivativeWindow, config.DerivativePolynomialOrder, ...
        config.DerivativeOrder, step);
end
result.Wavelength = x;
result.Value = y;
end

function result = rawSpectrum(sample, analysisRange)
% Prepare the unprocessed reflectance for preview without changing its scale.
x = sample.Wavelength(:); y = sample.Reflectance(:);
valid = isfinite(x) & isfinite(y); x = x(valid); y = y(valid);
[x,order] = sort(x); y = y(order);
[x,~,group] = unique(x); y = accumarray(group,y,[],@mean);
mask = x >= analysisRange(1) & x <= analysisRange(2);
result.Wavelength = x(mask); result.Value = y(mask);
if isempty(result.Wavelength)
    error('The selected display range does not contain data.');
end
end

function yOutput = applySg(yInput, window, order, derivative, spacing)
coefficient = sgCoefficients(window, order, derivative, spacing);
yInput = yInput(:);
halfWindow = (window-1)/2;
yOutput = nan(size(yInput));
for k = 1:numel(yInput)
    indices = (k-halfWindow):(k+halfWindow);
    indices(indices < 1) = 1;
    indices(indices > numel(yInput)) = numel(yInput);
    yOutput(k) = coefficient*yInput(indices);
end
end

function yOutput = gaussianSmooth(yInput, window)
yInput = yInput(:);
halfWindow = (window-1)/2;
sigma = max(window/6, eps);
positions = (-halfWindow:halfWindow).';
weights = exp(-0.5*(positions/sigma).^2);
yOutput = nan(size(yInput));
for k = 1:numel(yInput)
    indices = (k-halfWindow):(k+halfWindow);
    valid = indices >= 1 & indices <= numel(yInput);
    localWeights = weights(valid);
    localWeights = localWeights/sum(localWeights);
    yOutput(k) = sum(localWeights.*yInput(indices(valid)));
end
end

function label = ordinateLabel(config)
if config.DerivativeOrder == 0
    label = config.TransformName;
elseif config.DerivativeOrder == 1
    label = ['d/dlambda [', config.TransformName, ']'];
else
    label = ['d^2/dlambda^2 [', config.TransformName, ']'];
end
end

function textValue = workflowTitle(config)
if config.SequentialDerivative
    derivativeText = 'sequential first -> second derivative';
else
    derivativeText = sprintf('derivative order %d', config.DerivativeOrder);
end
textValue = sprintf('%s | %s | %s | %s | %s | %s', ...
    config.TransformName, config.BaselineName, config.ScatterName, ...
    config.NormalizationName, config.SmoothingName, derivativeText);
end

function lines = workflowDescription(config)
% Human-readable audit trail shown in the preview and review windows.
lines = {sprintf('Range: %.6g-%.6g nm',config.AnalysisRange(1), ...
    config.AnalysisRange(2))};
if config.GridStep > 0
    lines{end+1} = sprintf('Interpolation: uniform %.6g nm grid',config.GridStep);
else
    lines{end+1} = 'Interpolation: native wavelength grid';
end
lines{end+1} = ['Transformation: ',config.TransformName];
if config.Baseline ~= 1
    lines{end+1} = ['Baseline/continuum: ',config.BaselineName];
end
if config.Scatter ~= 1, lines{end+1} = ['Scatter correction: ',config.ScatterName]; end
if config.Normalization ~= 1
    lines{end+1} = ['Normalization: ',config.NormalizationName];
end
if config.Smoothing ~= 1
    lines{end+1} = sprintf('Smoothing: %s, window %d, polynomial %d', ...
        config.SmoothingName,config.SmoothWindow,config.SmoothPolynomialOrder);
end
if config.SequentialDerivative
    lines{end+1} = sprintf(['Derivative: sequential first derivative twice, ', ...
        'SG window %d, polynomial %d'],config.DerivativeWindow, ...
        config.DerivativePolynomialOrder);
elseif config.DerivativeOrder > 0
    lines{end+1} = sprintf('Derivative: order %d, SG window %d, polynomial %d', ...
        config.DerivativeOrder,config.DerivativeWindow, ...
        config.DerivativePolynomialOrder);
else
    lines{end+1} = 'Derivative: none';
end
end

function writeConfiguration(outputFile, config)
names = {'Analysis_start_nm';'Analysis_end_nm';'Grid_step_nm'; ...
    'Transformation';'Baseline_or_continuum';'Continuum_intervals_nm'; ...
    'Scatter_correction';'Normalization';'Smoothing'; ...
    'Smoothing_window_points';'Smoothing_polynomial_order'; ...
    'Derivative_order';'Derivative_window_points'; ...
    'Derivative_polynomial_order';'Sequential_derivative'; ...
    'Processing_order';'Method_note'; ...
    'Continuum_and_band_depth_reference'; ...
    'Soil_Vis_NIR_review';'Preprocessing_review';'SNV_reference'; ...
    'SG_reference'};
values = {config.AnalysisRange(1); config.AnalysisRange(2); ...
    config.GridStep; config.TransformName; config.BaselineName; ...
    mat2str(config.ContinuumRanges); config.ScatterName; ...
    config.NormalizationName; config.SmoothingName; config.SmoothWindow; ...
    config.SmoothPolynomialOrder; config.DerivativeOrder; ...
    config.DerivativeWindow; config.DerivativePolynomialOrder; ...
    config.SequentialDerivative; ...
    ['Transformation -> baseline/continuum -> scatter correction -> ', ...
    'normalization -> smoothing -> derivative']; ...
    ['Generic spectral processing only; mineral abundance requires an ', ...
    'independently validated calibration.']; ...
    'Clark and Roush (1984), JGR 89(B7), 6329-6340'; ...
    'Piccini et al. (2024), European Journal of Soil Science 75, e13481'; ...
    'Yan et al. (2025), iScience 28, 112759'; ...
    'Barnes et al. (1989), Applied Spectroscopy 43, 772-777'; ...
    'Savitzky and Golay (1964), Analytical Chemistry 36, 1627-1639'};
writetable(table(names, values, 'VariableNames', {'Parameter','Value'}), ...
    outputFile, 'Sheet', 'Workflow');
end

function validateOddWindow(window, order, isPolynomial)
if ~isfinite(window) || window < 3 || mod(window, 2) == 0
    error('The window must be an odd integer of at least 3 points.');
end
if isPolynomial && (~isfinite(order) || order < 0 || order >= window)
    error('Polynomial order must be nonnegative and smaller than the window.');
end
end

function samples = collectAllSamples(inputFolder, outputFile)
extensions = {'*.csv','*.txt','*.asc','*.dat','*.xlsx','*.xls'};
files = [];
for k = 1:numel(extensions)
    files = [files; dir(fullfile(inputFolder, extensions{k}))]; %#ok<AGROW>
end
samples = struct('Name', {}, 'Wavelength', {}, 'Reflectance', {});
usedNames = containers.Map('KeyType', 'char', 'ValueType', 'double');
for fileIndex = 1:numel(files)
    inputFile = fullfile(files(fileIndex).folder, files(fileIndex).name);
    if startsWith(files(fileIndex).name, '.') || ...
            (isLegacyResultFile(files(fileIndex).name) || ...
            startsWith(files(fileIndex).name, 'ZLSpectra_DIY_', 'IgnoreCase', true) || ...
            startsWith(files(fileIndex).name, 'ZLSpectra_Advanced_', 'IgnoreCase', true) || ...
            startsWith(files(fileIndex).name, 'ZLSpectra_Configurable_', 'IgnoreCase', true)) || ...
            (~isempty(outputFile) && strcmpi(inputFile, outputFile))
        continue;
    end
    [~, baseName] = fileparts(files(fileIndex).name);
    try
        [headers, numericData, sampleCount] = readAllSamples(inputFile);
    catch ME
        warning('Skipping file %s: %s', files(fileIndex).name, ME.message); continue;
    end
    for sampleIndex = 1:sampleCount
        wavelengthColumn = 2*sampleIndex-1; reflectanceColumn = 2*sampleIndex;
        if sampleCount == 1
            sampleName = baseName;
        else
            sampleName = sampleValueToText(headers{wavelengthColumn});
            if isempty(sampleName)
                sampleName = sprintf('%s_sample_%d', baseName, sampleIndex);
            end
        end
        sampleName = makeUniqueName(sampleName, usedNames);
        valid = isfinite(numericData(:, wavelengthColumn)) & ...
            isfinite(numericData(:, reflectanceColumn));
        if nnz(valid) < 7, continue; end
        samples(end+1).Name = sampleName; %#ok<AGROW>
        samples(end).Wavelength = numericData(valid, wavelengthColumn);
        samples(end).Reflectance = numericData(valid, reflectanceColumn);
    end
end
end

function [headerFields, numericData, sampleCount] = readAllSamples(inputFile)
[~, ~, extension] = fileparts(inputFile);
if any(strcmpi(extension, {'.xlsx','.xls'}))
    allCells = readcell(inputFile);
    if isempty(allCells), error('The file is empty.'); end
    headerFields = allCells(1, :);
    numericData = readmatrix(inputFile, 'NumHeaderLines', 2);
else
    fileID = fopen(inputFile, 'r');
    if fileID == -1, error('Cannot open the file.'); end
    cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
    firstLine = fgetl(fileID);
    if ~ischar(firstLine), error('The file has no first row.'); end
    headerFields = strsplit(firstLine, ',', 'CollapseDelimiters', false);
    if feof(fileID), error('The file has fewer than two rows.'); end
    fgetl(fileID);
    rows = {}; maximumColumns = 0;
    while ~feof(fileID)
        oneLine = fgetl(fileID);
        if ~ischar(oneLine) || isempty(strtrim(oneLine)), continue; end
        fields = strsplit(oneLine, ',', 'CollapseDelimiters', false);
        if numel(fields) < 2, fields = regexp(oneLine, '[;\t]', 'split'); end
        values = nan(1, numel(fields));
        for c = 1:numel(fields), values(c) = str2double(strtrim(fields{c})); end
        rows{end+1, 1} = values; %#ok<AGROW>
        maximumColumns = max(maximumColumns, numel(values));
    end
    numericData = nan(numel(rows), maximumColumns);
    for r = 1:numel(rows), numericData(r, 1:numel(rows{r})) = rows{r}; end
end
nonempty = any(isfinite(numericData), 1);
lastColumn = find(nonempty, 1, 'last');
if isempty(lastColumn) || lastColumn < 2, error('No valid column pair found.'); end
numericData = numericData(:, 1:lastColumn);
if mod(size(numericData, 2), 2) ~= 0, numericData = numericData(:, 1:end-1); end
sampleCount = size(numericData, 2)/2;
end

function samples = sortSamplesByNumber(samples)
if numel(samples) < 2, return; end
numbers = inf(numel(samples), 1);
for k = 1:numel(samples)
    token = regexp(samples(k).Name, '[+-]?(?:\d+\.?\d*|\.\d+)', ...
        'match', 'once');
    if ~isempty(token), numbers(k) = str2double(token); end
end
original = (1:numel(samples))';
[~, order] = sortrows([isinf(numbers), numbers, original], [1 2 3]);
samples = samples(order);
end

function name = makeUniqueName(name, usedNames)
name = strtrim(char(name));
if isempty(name), name = 'Unnamed_sample'; end
key = lower(name);
if isKey(usedNames, key)
    usedNames(key) = usedNames(key)+1;
    name = sprintf('%s_%d', name, usedNames(key));
else
    usedNames(key) = 1;
end
end

function textValue = sampleValueToText(value)
if isnumeric(value) && isscalar(value) && isfinite(value)
    textValue = num2str(value, '%.15g');
elseif ischar(value) || isstring(value)
    textValue = strtrim(char(string(value)));
    if strcmpi(textValue, '<missing>'), textValue = ''; end
else
    textValue = '';
end
end

function coefficient = sgCoefficients(window, order, derivative, spacing)
halfWindow = (window-1)/2;
x = (-halfWindow:halfWindow).';
design = zeros(window, order+1);
for power = 0:order, design(:, power+1) = x.^power; end
selector = zeros(1, order+1);
selector(derivative+1) = factorial(derivative)/spacing^derivative;
coefficient = selector/(design.'*design)*design.';
end


function runEstablishedMineralModule(mineralChoice)
%% anli3 - Interactive mineral-band analysis of DRS second derivatives
% Reads single- and multi-spectrum files; the first row supplies sample IDs.
% Pure-mineral reference spectra are embedded below; no reference CSV is
% required when distributing this single .m file.
% Select one second-derivative minimum and one maximum per sample, in either
% wavelength order. Clay panels show literature bands, not synthetic spectra.
% Confirmed selections are saved immediately and can be resumed or revised.
%
% Method provenance (do not interpret the window combinations as published):
% - Hematite and goethite: this script uses a 5-point quadratic SG smoother
%   followed by a 29-point quadratic SG second derivative. The 5+29 choice
%   is a local analysis setting, NOT a window combination prescribed by
%   Torrent and Barron (2008). That chapter supports K-M transformation,
%   derivative spectroscopy, smoothing and approximate Fe-oxide band pairs.
% - Gypsum and CaCO3: this script uses 5+39 with the same two-stage design.
%   Zhang et al. (2025) and Cao et al. (2024) report an SG factor of 39 and
%   the mineral bands, but do NOT prescribe this added 5-point pre-smoother.
%
% References:
% Coblinski, J. A. et al. (2021), Identification of minerals in subtropical
%   soils with different textural classes by VIS-NIR-SWIR reflectance
%   spectroscopy, CATENA 203, 105334, DOI:10.1016/j.catena.2021.105334.
% Clay processing: 5-point/order-2 R presmoothing, then SG D2(F(R)).
% Poppiel et al. (2020), Remote Sensing 12,1197, doi:10.3390/rs12071197:
%   Kt 2205/2225 nm; quadratic/40-smoothing points.
%   Default 41 points here is NOT a verified equivalent of that setting.
% Coblinski et al. (2021): R -> K-M -> second derivative; 35 window
%   points; polynomial order not reported. The Unscrambler for K-M/SD;
%   R/prospectr continuum removal is a separate mineral-identification step.
%   FieldSpec Pro 350-2500 nm spectra interpolated to 1 nm.
% Rosin et al. (2023), Geoderma 432,116413,
%   doi:10.1016/j.geoderma.2023.116413: R -> K-M -> SG D2;
%   derivative order m=2, polynomial order p=3, window w=25.
%   Input 350-2500 nm at 1 nm; reported derivative output 412-2478 nm
%   describes that study, not this program's processing boundaries.
% Published Poppiel processing uses The Unscrambler on 1 nm data.
% Il markers 2344/2372 nm and Ch markers 2372/2395 nm are nominal
%   user-selected boundaries, not guaranteed extrema in the cited studies.
% Added five-point R smoothing and local 41-point/order-2 settings
%   are program settings, not published parameter combinations.
% Torrent, J. & Barron, V. (2008), Diffuse Reflectance Spectroscopy,
%   Methods of Soil Analysis, Part 5, Ch. 13, DOI: 10.2136/sssabookser5.5.c13.
% Savitzky, A. & Golay, M. J. E. (1964), Smoothing and Differentiation
%   of Data by Simplified Least Squares Procedures, Anal. Chem. 36,
%   1627-1639, DOI: 10.1021/ac60214a047 (general SG algorithm).
% Zhang, J. et al. (2025), A Novel Approach of Semi-Quantifying Gypsum in
%   Sedimentary Rocks by Visible and Near-Infrared Diffuse Reflectance
%   Spectroscopy, Geochem. Geophys. Geosyst., DOI: 10.1029/2024GC012118.
% Cao, W. et al. (2024), Semi-Quantification of the Calcium Carbonate in
%   Marine Sediments by Visible and Near-Infrared Diffuse Reflectance
%   Spectroscopy, Geochem. Geophys. Geosyst., DOI: 10.1029/2023GC011370.
% No Signal Processing Toolbox is required.

clc; close all;

%% Parameters
preSmoothWindow = 5;
derivativeWindow = 29; % Automatically set to 39 for gypsum/CaCO3.
polynomialOrder = 2;

%% Select input folder, mineral, processing method and output file
uiwait(msgbox('Select the folder containing the spectra.', ...
    'Step 1: Input folder', 'modal'));
inputFolder = uigetdir(pwd, 'Select the folder containing the spectra');
if isequal(inputFolder, 0), error('No input folder selected.'); end
fprintf('1. Input folder: %s\n', inputFolder);

isClay = any(strcmp(mineralChoice, ...
    {'Kaolinite','Illite','Chlorite','2:1 clay minerals','Gibbsite'}));
fprintf('2. Target mineral: %s\n', mineralChoice);

% Gypsum has two separately selectable indices (Zhang et al., 2025).
gypsumIndicator = '';
nextStepNumber = 3;
if strcmp(mineralChoice, 'Gypsum')
    gypsumIndicatorOptions = {'I_Gy1540: minimum ~1540, maximum ~1566 nm', ...
        'I_Gy1942: minimum ~1942, maximum ~1965 nm'};
    [gypsumIndicatorIndex, selected] = listdlg( ...
        'PromptString', 'Select the gypsum spectral index (Zhang et al., 2025):', ...
        'SelectionMode', 'single', ...
        'ListString', gypsumIndicatorOptions, ...
        'InitialValue', 1, 'Name', 'Step 3: Gypsum index', ...
        'ListSize', [390 130]);
    if ~selected, error('No gypsum index selected.'); end
    if gypsumIndicatorIndex == 1
        gypsumIndicator = '1540';
    else
        gypsumIndicator = '1942';
    end
    fprintf('3. Gypsum index: I_%s (Zhang et al., 2025)\n', gypsumIndicator);
    nextStepNumber = 4;
end

% Clay proxies: 5-point/order-2 SG on R, then K-M and SG D2(F(R)).
% Poppiel et al. (2020) reports quadratic/40-smoothing points.
% The odd window below is a local setting, not an asserted 40-point equivalent.
if isClay
    isRosinPreset = strcmp(mineralChoice,'Gibbsite');
    if strcmp(mineralChoice,'Kaolinite')
        [presetIndex, presetChosen] = listdlg( ...
            'PromptString','Choose a kaolinite processing preset:', ...
            'SelectionMode','single','ListString', ...
            {'Local 41-point/order-2 setting (Poppiel band positions)', ...
             'Rosin et al. (2023): 25-point/order-3 SG'}, ...
            'InitialValue',1,'ListSize',[510 100],'Name','Kaolinite preset');
        if ~presetChosen, return; end
        isRosinPreset = presetIndex == 2;
    end
    if isRosinPreset
        sgDefaults = {'25','3'};
        sgWindowPrompt = 'SG window: odd integer (Rosin preset: 25 points)';
        processingContext = 'Rosin et al. (2023); doi:10.1016/j.geoderma.2023.116413';
        publishedSetting = 'R -> KM -> SG D2; m=2, p=3, w=25; input 350-2500 nm at 1 nm; reported output 412-2478 nm';
        windowExplanation = 'Explicit published 25-point setting; actual settings recorded separately';
    else
        sgDefaults = {'41','2'};
        sgWindowPrompt = 'SG window: odd integer (41 is a local default; published setting recorded separately)';
        processingContext = 'Poppiel et al. (2020); doi:10.3390/rs12071197';
        publishedSetting = 'R -> KM -> D2; polynomial order 2; 40-smoothing points; The Unscrambler; 1 nm data';
        windowExplanation = 'Actual odd window is local; equivalence to published 40 unverified';
    end
    if any(strcmp(mineralChoice, {'Illite','Chlorite'}))
        processingContext = 'Coblinski et al. (2021); doi:10.1016/j.catena.2021.105334';
        publishedSetting = ['R -> KM -> D2; 35 window points; polynomial order not reported; ', ...
            'The Unscrambler; FieldSpec Pro 350-2500 nm interpolated to 1 nm; ', ...
            'continuum removal separately in R/prospectr for mineral identification'];
        windowExplanation = ['Actual SG window and polynomial order are local settings; ', ...
            'published 35-point window does not establish a polynomial order'];
    end
    if strcmp(mineralChoice,'2:1 clay minerals')
        uiwait(msgbox(['This is a GROUP spectral proxy. It does not resolve individual ', ...
            'illite, chlorite, vermiculite or montmorillonite contents. ', ...
            'Do not add its amplitude to the separate illite/chlorite amplitudes.'], ...
            '2:1 clay mineral group','modal'));
    end
    processingMethod = 'clayTwoStageSG';
    preSmoothWindow = 5;
    while true
        settings = inputdlg({ ...
            sgWindowPrompt, ...
            'Polynomial order (integer >= 2 and less than window)'}, ...
            'Clay proxies: SG second derivative after 5-point R smoothing', ...
            [1 90], sgDefaults);
        if isempty(settings), return; end
        derivativeWindow = str2double(settings{1});
        polynomialOrder = str2double(settings{2});
        if isfinite(derivativeWindow) && derivativeWindow == fix(derivativeWindow) ...
                && derivativeWindow >= 3 && mod(derivativeWindow,2) == 1 ...
                && isfinite(polynomialOrder) && polynomialOrder == fix(polynomialOrder) ...
                && polynomialOrder >= 2 && polynomialOrder < derivativeWindow
            break;
        end
        uiwait(errordlg(['Use an odd window and an integer polynomial order ', ...
            'at least 2 and smaller than the window.'], ...
            'Invalid SG settings','modal'));
    end
    methodDisplayName = sprintf('SG R smoothing (5 points, order 2) + D2(F(R)) (%d points, order %d)', ...
        derivativeWindow, polynomialOrder);
    methodFileTag = sprintf('SG_R5_P2_D2_%d_P%d', derivativeWindow, polynomialOrder);
    saveStepNumber = nextStepNumber+1;
else
    % Existing Fe oxide, gypsum and carbonate processing is retained.
    if any(strcmp(mineralChoice, {'Gypsum','Calcium carbonate'}))
        derivativeWindow = 39;
    else
        derivativeWindow = 29;
    end
    processingMethod = 'sgWindow';
    methodDisplayName = sprintf('Two-stage SG (5+%d points)', derivativeWindow);
    methodFileTag = sprintf('SG_5+%d', derivativeWindow);
    saveStepNumber = nextStepNumber;
end
fprintf('%d. Processing method: %s\n', nextStepNumber, methodDisplayName);

switch mineralChoice
    case 'Hematite'
        analysisRange = [380 900];
        displayRange = [500 625];
        mineralSheetName = 'Hematite';
        bandCitation = 'Liu et al. (2011)';
        literatureValleyNm = 535;
        literaturePeakNm = 580;
        literatureValleyRange = [535 575];
        literaturePeakRange = [565 605];
        amplitudeSymbol = 'I_{Hm}';
    case 'Goethite'
        analysisRange = [380 900];
        displayRange = [400 500];
        mineralSheetName = 'Goethite';
        bandCitation = 'Jiang et al. (2014); 425/455 nm: nominal selection guides';
        literatureValleyNm = 425;
        literaturePeakNm = 455;
        literatureValleyRange = [415 435];
        literaturePeakRange = [440 455];
        amplitudeSymbol = 'I_{Gt}';
    case 'Gypsum'
        analysisRange = [350 2600];
        if strcmp(gypsumIndicator, '1942')
            displayRange = [1900 2000];
            mineralSheetName = 'Gypsum_I1942';
            literatureValleyNm = 1942;
            literaturePeakNm = 1965;
            amplitudeSymbol = 'I_{Gy1942}';
        else
            displayRange = [1500 1600];
            mineralSheetName = 'Gypsum_I1540';
            literatureValleyNm = 1540;
            literaturePeakNm = 1566;
            amplitudeSymbol = 'I_{Gy1540}';
        end
        literatureValleyRange = [NaN NaN];
        literaturePeakRange = [NaN NaN];
        bandCitation = 'Zhang et al. (2025)';
    case 'Calcium carbonate'
        analysisRange = [350 2600];
        displayRange = [2300 2400];
        mineralSheetName = 'Calcium_carbonate';
        literatureValleyNm = 2340;
        literaturePeakNm = 2370;
        literatureValleyRange = [NaN NaN];
        literaturePeakRange = [NaN NaN];
        amplitudeSymbol = 'I_{Cc}';
        bandCitation = 'Cao et al. (2024)';
    case 'Kaolinite'
        analysisRange = [350 2600]; displayRange = [2160 2260];
        mineralSheetName = 'Kaolinite'; amplitudeSymbol = 'I_{Kt}';
        literatureValleyNm = 2205; literaturePeakNm = 2225;
        literatureValleyRange = [NaN NaN]; literaturePeakRange = [NaN NaN];
        bandCitation = 'Poppiel et al. (2020); doi:10.3390/rs12071197';
    case 'Illite'
        analysisRange = [350 2600]; displayRange = [2300 2400];
        mineralSheetName = 'Illite'; amplitudeSymbol = 'I_{Il}';
        literatureValleyNm = 2344; literaturePeakNm = 2372;
        literatureValleyRange = [NaN NaN]; literaturePeakRange = [2360 2372];
        bandCitation = ['Coblinski et al. (2021); 2344/2372 nm: user-requested nominal markers; ', ...
            'exact minimum search interval unverified'];
    case 'Chlorite'
        analysisRange = [350 2600]; displayRange = [2320 2420];
        mineralSheetName = 'Chlorite'; amplitudeSymbol = 'I_{Ch}';
        literatureValleyNm = 2395; literaturePeakNm = 2372;
        literatureValleyRange = [2372 2395]; literaturePeakRange = [2355 2370];
        bandCitation = ['Coblinski et al. (2021); user-specified boundaries: 2372 / 2395 nm; ', ...
            'reference only, not fixed extremum positions'];
    case '2:1 clay minerals'
        analysisRange = [350 2600]; displayRange = [1840 1960];
        mineralSheetName = 'Clay_2to1'; amplitudeSymbol = 'I_{2:1}';
        literatureValleyNm = NaN; literaturePeakNm = NaN;
        literatureValleyRange = [1900 1925]; literaturePeakRange = [1870 1895];
        bandCitation = 'Poppiel et al. (2020); group proxy; doi:10.3390/rs12071197';
    case 'Gibbsite'
        analysisRange = [350 2600]; displayRange = [2250 2305];
        mineralSheetName = 'Gibbsite'; amplitudeSymbol = 'I_{Gb}';
        literatureValleyNm = 2265; literaturePeakNm = 2295;
        literatureValleyRange = [NaN NaN]; literaturePeakRange = [NaN NaN];
        bandCitation = 'Rosin et al. (2023); doi:10.1016/j.geoderma.2023.116413';
end
% Only the 2:1 group uses range references; all other minerals use lines.
if ~strcmp(mineralChoice,'2:1 clay minerals')
    literatureValleyRange = [NaN NaN];
    literaturePeakRange = [NaN NaN];
end
if strcmp(mineralChoice,'Kaolinite') && isRosinPreset
    displayRange = [2190 2240];
    bandCitation = 'Rosin et al. (2023); doi:10.1016/j.geoderma.2023.116413';
end
if derivativeWindow == 39
    if strcmp(mineralChoice, 'Gypsum')
        methodCitation = 'SG factor 39: Zhang et al. (2025); 5+39: local adaptation';
    else
        methodCitation = 'SG factor 39: Cao et al. (2024); 5+39: local adaptation';
    end
else
    methodCitation = ['DRS basis: Torrent & Barron (2008); ', ...
        '5+29: local analysis setting'];
end
if isClay
    if isRosinPreset
        if derivativeWindow == 25 && polynomialOrder == 3
            settingLabel = 'Rosin et al. (2023) SG parameters';
        else
            settingLabel = 'User-modified Rosin preset';
        end
        methodCitation = [methodDisplayName, '; ', settingLabel, '; 5-point/order-2 R presmoothing: local addition'];
    else
        methodCitation = [methodDisplayName, ...
            '; processing reference: ', processingContext, ...
            '; actual SG settings are local; 5-point/order-2 R presmoothing: local addition'];
    end
end
uiwait(msgbox('Select the output location and Excel file name.', ...
    sprintf('Step %d: Save results', saveStepNumber), 'modal'));
[outputName, outputDir] = uiputfile('*.xlsx', 'Save results to:', ...
    fullfile(inputFolder, [mineralSheetName, '_', methodFileTag, ...
    '_interactive_selections.xlsx']));
if isequal(outputName, 0), error('No output file selected.'); end
outputFile = fullfile(outputDir, outputName);
fprintf('%d. Output file: %s\n', saveStepNumber, outputFile);

% Resume clay selections only when the saved numerical settings match.
if isClay
    expectedSettings = {'Mineral',mineralChoice; ...
        'SG_window_points',derivativeWindow; ...
        'SG_polynomial_order',polynomialOrder; 'SG_derivative_order',2; ...
        'Grid_spacing_nm',1; 'Reflectance_presmoothing','SG: 5 points; polynomial order 2'; ...
        'Normalization','None'; ...
        'Boundary_handling','Valid convolution; no endpoint padding'};
    if any(strcmp(mineralChoice, {'Gibbsite','2:1 clay minerals'})) || isRosinPreset
        expectedSettings(end+1,:) = {'Display_range_nm',mat2str(displayRange)};
    end
    while isfile(outputFile)
        [canResume, reason] = est_clayResumeCompatible( ...
            outputFile, mineralSheetName, expectedSettings, inputFolder);
        if canResume
            fprintf('Existing workbook has matching clay settings; resuming saved selections.\n');
            break;
        end
        uiwait(msgbox(sprintf(['Existing results cannot be resumed: %s\n', ...
            'Select another output filename. The existing workbook will be kept.'], reason), ...
            'Select another output file','modal'));
        [outputName, outputDir] = uiputfile('*.xlsx', ...
            'Save with a different filename (Cancel to stop):', ...
            fullfile(outputDir, [mineralSheetName, '_', methodFileTag, '_new.xlsx']));
        if isequal(outputName,0), return; end
        outputFile = fullfile(outputDir, outputName);
        fprintf('Output file: %s\n',outputFile);
    end
end
% Resume previously confirmed selections; matching sample IDs are skipped.
selectedRows = est_readExistingSelections(outputFile, mineralSheetName);
if isClay && ~isfile(outputFile)
    if isRosinPreset
        sourceArticle = 'Rosin et al. (2023), Mapping Brazilian soil mineralogy using proximal and remote sensing data, Geoderma 432, 116413';
        sourceDOI = '10.1016/j.geoderma.2023.116413';
    elseif any(strcmp(mineralChoice, {'Kaolinite','2:1 clay minerals'}))
        sourceArticle = 'Poppiel et al. (2020), Soil color and mineralogy mapping using proximal and remote sensing in Midwest Brazil, Remote Sensing 12, 1197';
        sourceDOI = '10.3390/rs12071197';
    else
        sourceArticle = 'Coblinski et al. (2021), Identification of minerals in subtropical soils with different textural classes by VIS-NIR-SWIR reflectance spectroscopy, CATENA 203, 105334';
        sourceDOI = '10.1016/j.catena.2021.105334';
    end
    writecell({'Field','Value'; 'Mineral',mineralChoice; ...
        'Input_folder',inputFolder; ...
        'Band_source',bandCitation; ...
        'Article',sourceArticle; 'DOI',sourceDOI; ...
        'Minimum_nominal_nm',literatureValleyNm; ...
        'Maximum_nominal_nm',literaturePeakNm; ...
        'Display_range_nm',mat2str(displayRange); ...
        'Minimum_range_nm',mat2str(literatureValleyRange); ...
        'Maximum_range_nm',mat2str(literaturePeakRange); ...
        'Processing',methodCitation; ...
        'Transform','R -> SG smoothing (5 points/order 2) -> (1-R)^2/(2*R) -> SG second derivative'; ...
        'SG_window_points',derivativeWindow; 'SG_polynomial_order',polynomialOrder; ...
        'SG_derivative_order',2; 'Grid_spacing_nm',1; ...
        'Reflectance_presmoothing','SG: 5 points; polynomial order 2'; 'Normalization','None'; ...
        'Boundary_handling','Valid convolution; no endpoint padding'; ...
        'Processing_context',processingContext; ...
        'Published_setting',publishedSetting; ...
        'Window_equivalence',windowExplanation; ...
        'Il_Ch_processing','Coblinski et al. (2021): 35 window points; polynomial order not reported; actual settings and added R smoothing are local'; ...
        'Band_selection','Markers guide manual selection; they do not force endpoints to be extrema'; ...
        'Amplitude','D2(maximum) - D2(minimum); not a calibrated mass fraction'; ...
        'Selection','All displayed extrema selectable; maximum may precede minimum'; ...
        'Group_interpretation','2:1 is a group proxy, not individual mineral contents; do not sum with Il/Ch amplitudes'; ...
        'Missing_reference','NaN means no verified nominal position or interval'}, ...
        outputFile,'Sheet',[mineralSheetName '_Reference']);
end

if ~isempty(selectedRows)
    fprintf('Loaded %d prior selections; these samples will be skipped.\n', ...
        size(selectedRows, 1));
end

%% Read all single- and multi-spectrum files in the input folder
samples = est_collectAllSamples(inputFolder, outputFile);
if isempty(samples)
    errordlg(['No input spectra found after excluding ZLSpectra result files. ', ...
        'Select a folder containing original wavelength-reflectance data.'], ...
        'No input spectra');
    return;
end
samples = est_sortSamplesByNumber(samples);
allSamples = samples; % Preserve for review and editing via the trend plot.
allSampleCount = numel(samples);
if ~isempty(selectedRows)
    completedNames = string(selectedRows(:, 1));
    samples = samples(~ismember(string({samples.Name}), completedNames));
end
fprintf('Spectra: %d total, %d completed, %d remaining.\n', ...
    allSampleCount, size(selectedRows, 1), numel(samples));

%% Process the pure-mineral reference spectrum
% Hematite is assessed directly from each sample. Its literature positions
% are shown on the sample panel, so no pure-mineral reference panel is built.
if ~strcmp(mineralChoice, 'Hematite') && ~isClay
    [referenceWavelengthRaw, referenceReflectanceRaw] = ...
        est_embeddedReferenceSpectrum(mineralChoice);
    [referenceWavelength, referenceReflectance] = est_makeProcessingGrid( ...
        referenceWavelengthRaw, referenceReflectanceRaw, processingMethod, ...
        analysisRange);
    referenceResult = est_calculateSpectrumD2(referenceWavelength, ...
        referenceReflectance, processingMethod, preSmoothWindow, ...
        derivativeWindow, polynomialOrder, displayRange);
end

%% Interactive figure and sample loop
figureHandle = figure('Name', ['DRS | ', methodDisplayName, ' | Interactive selection'], ...
    'Color', 'w', 'Position', [50 40 1450 950], ...
    'NumberTitle', 'off');
setappdata(figureHandle, 'StopRequested', false);
setappdata(figureHandle, 'PendingSGWindow', []);
setappdata(figureHandle, 'SGGuideWindows', []);
setappdata(figureHandle, 'SelectedRows', selectedRows);
editContext.AllSamples = allSamples;
editContext.OutputFile = outputFile;
editContext.SheetName = mineralSheetName;
editContext.AmplitudeSymbol = amplitudeSymbol;
editContext.PreSmoothWindow = preSmoothWindow;
editContext.DerivativeWindow = derivativeWindow;
editContext.PolynomialOrder = polynomialOrder;
editContext.ProcessingMethod = processingMethod;
editContext.DisplayRange = displayRange;
editContext.AnalysisRange = analysisRange;
editContext.LiteratureValleyNm = literatureValleyNm;
editContext.LiteraturePeakNm = literaturePeakNm;
editContext.LiteratureValleyRange = literatureValleyRange;
editContext.LiteraturePeakRange = literaturePeakRange;
editContext.BandCitation = bandCitation;
editContext.MethodCitation = methodCitation;
setappdata(figureHandle, 'EditContext', editContext);

for savedIndex = 1:size(selectedRows,1)
    est_recordSGSettings(outputFile,mineralSheetName,selectedRows{savedIndex,1}, ...
        derivativeWindow,polynomialOrder,false);
end
processingFailures = 0; missingPairs = 0;
for sampleIndex = 1:numel(samples)
    if ~isgraphics(figureHandle) || getappdata(figureHandle, 'StopRequested')
        break;
    end
    sample = samples(sampleIndex);
    try
        validWavelengths = sample.Wavelength(isfinite(sample.Wavelength) & ...
            isfinite(sample.Reflectance));
        if isempty(validWavelengths) || ...
                min(validWavelengths) > displayRange(1) || ...
                max(validWavelengths) < displayRange(2)
            error(['Spectrum range %.1f-%.1f nm does not cover the selected ', ...
                '%s analysis display band %.1f-%.1f nm. Use original spectra ', ...
                'covering this band; interpolation cannot supply missing measurements.'], ...
                min(validWavelengths),max(validWavelengths),mineralChoice, ...
                displayRange(1),displayRange(2));
        end
        [wavelength, reflectance] = est_makeProcessingGrid( ...
            sample.Wavelength, sample.Reflectance, processingMethod, ...
            analysisRange);
        result = est_calculateSpectrumD2(wavelength, reflectance, ...
            processingMethod, preSmoothWindow, derivativeWindow, ...
            polynomialOrder, displayRange);
    catch ME
        processingFailures = processingFailures + 1;
        warning('Failed to process sample %s: %s', sample.Name, ME.message);
        continue;
    end

    if strcmp(mineralChoice,'2:1 clay minerals')
        result = est_filterClayGroupExtrema(result);
    end
    minimumMask = strcmp(result.ExtremaType, 'mini');
    maximumMask = strcmp(result.ExtremaType, 'max');
    minimumIndices = result.ExtremaIndex(minimumMask);
    maximumIndices = result.ExtremaIndex(maximumMask);
    if isempty(minimumIndices) || isempty(maximumIndices)
        missingPairs = missingPairs + 1;
        warning('No complete minimum/maximum pair in the displayed band for %s; skipped.', sample.Name);
        continue;
    end

    confirmed = false;
    while ~confirmed && isgraphics(figureHandle)
        pendingWindow = getappdata(figureHandle,'PendingSGWindow');
        if ~isempty(pendingWindow)
            setappdata(figureHandle,'PendingSGWindow',[]);
            try
                updatedResult = est_calculateSpectrumD2(wavelength,reflectance, ...
                    processingMethod,preSmoothWindow,pendingWindow,polynomialOrder,displayRange);
                if strcmp(mineralChoice,'2:1 clay minerals')
                    updatedResult = est_filterClayGroupExtrema(updatedResult);
                end
                updatedMin = updatedResult.ExtremaIndex(strcmp(updatedResult.ExtremaType,'mini'));
                updatedMax = updatedResult.ExtremaIndex(strcmp(updatedResult.ExtremaType,'max'));
                if isempty(updatedMin) || isempty(updatedMax)
                    error('No complete candidate pair with this SG window.');
                end
                derivativeWindow = pendingWindow; result = updatedResult;
                minimumIndices = updatedMin; maximumIndices = updatedMax;
                methodCitation = sprintf('User-selected SG D2: %d points, order %d; R presmoothing: 5 points/order 2; grid 1 nm',derivativeWindow,polynomialOrder);
                editContext.DerivativeWindow = derivativeWindow;
                editContext.MethodCitation = methodCitation;
                setappdata(figureHandle,'EditContext',editContext);
                if ~strcmp(mineralChoice,'Hematite') && ~isClay
                    referenceResult = est_calculateSpectrumD2(referenceWavelength, ...
                        referenceReflectance,processingMethod,preSmoothWindow, ...
                        derivativeWindow,polynomialOrder,displayRange);
                end
            catch ME
                uiwait(errordlg(ME.message,'SG window unchanged'));
            end
        end
        setappdata(figureHandle,'SGCurrentInput',{wavelength,reflectance,processingMethod,preSmoothWindow,polynomialOrder,displayRange});
        selectedRows = getappdata(figureHandle, 'SelectedRows');
        clf(figureHandle);
        est_createStopButton(figureHandle);
        est_createSGWindowButton(figureHandle,derivativeWindow);
        est_createSGGuideButton(figureHandle);
        % Main spectrum fills the upper two rows; summaries use the bottom.
        % SG guides and literature markers are drawn on the sample itself.
        layout = tiledlayout(figureHandle, 3, 2, ...
            'TileSpacing', 'compact', 'Padding', 'compact');
        layout.OuterPosition = [0 0 1 0.92];

        if ~strcmp(mineralChoice,'Hematite') && ~isClay
            referenceAxes = nexttile(layout,5);
            plot(referenceAxes,referenceResult.Wavelength,referenceResult.D2, ...
                'k-','LineWidth',1.2); hold(referenceAxes,'on');
            yline(referenceAxes,0,':','Color',[0.65 0.65 0.65]);
            est_plotReferenceExtrema(referenceAxes,referenceResult);
            est_drawLiteratureReference(referenceAxes,literatureValleyNm, ...
                literaturePeakNm,literatureValleyRange,literaturePeakRange,bandCitation);
            xlim(referenceAxes,displayRange);grid(referenceAxes,'on');
            xlabel(referenceAxes,'Wavelength (nm)');
            ylabel(referenceAxes,'d^2F(R)/d\lambda^2');
            title(referenceAxes,'Reference mineral');
        end

        %% Middle: all local extrema in the current sample are selectable
        sampleAxes = nexttile(layout,1,[2 2]);
        sampleAxes.FontSize = 11;
        mainCurve = plot(sampleAxes, result.Wavelength, result.D2, 'k-', ...
            'LineWidth', 1.15, 'Tag','SGMainCurve'); hold(sampleAxes, 'on');
        yline(sampleAxes, 0, ':', 'Color', [0.65 0.65 0.65]);
        plot(sampleAxes, result.Wavelength(minimumIndices), ...
            result.D2(minimumIndices), 'v', 'LineStyle', 'none', ...
            'MarkerSize', 7, 'MarkerFaceColor', [0.55 0.72 1], ...
            'MarkerEdgeColor', [0 0.25 0.8]);
        plot(sampleAxes, result.Wavelength(maximumIndices), ...
            result.D2(maximumIndices), '^', 'LineStyle', 'none', ...
            'MarkerSize', 7, 'MarkerFaceColor', [1 0.65 0.5], ...
            'MarkerEdgeColor', [0.8 0.1 0]);
        if strcmp(mineralChoice, 'Hematite')
            est_drawHematiteLiteratureLines(sampleAxes, literatureValleyNm, ...
                literaturePeakNm, bandCitation);
        else
            est_drawLiteratureReference(sampleAxes, literatureValleyNm, ...
                literaturePeakNm, literatureValleyRange, literaturePeakRange, ...
                bandCitation);
        end
        setappdata(figureHandle,'SGGuideAxes',sampleAxes);
        setappdata(figureHandle,'SGMainWindow',derivativeWindow);
        est_drawSGGuides(figureHandle);
        xlim(sampleAxes, displayRange);
        est_labelExtrema(sampleAxes, result, minimumIndices, 'Min', [0 0.25 0.8]);
        est_labelExtrema(sampleAxes, result, maximumIndices, 'Max', [0.8 0.1 0]);
        grid(sampleAxes, 'on');
        xlabel(sampleAxes, 'Wavelength (nm)');
        ylabel(sampleAxes, 'd^2F(R)/d\lambda^2');
        if any(strcmp(mineralChoice, {'Chlorite','2:1 clay minerals'}))
            firstPrompt = 'a maximum (red)'; secondPrompt = 'a minimum (blue)';
            firstCandidates = maximumIndices; secondCandidates = minimumIndices;
            firstColor = 'r'; secondColor = 'b';
        else
            firstPrompt = 'a minimum (blue)'; secondPrompt = 'a maximum (red)';
            firstCandidates = minimumIndices; secondCandidates = maximumIndices;
            firstColor = 'b'; secondColor = 'r';
        end
        title(sampleAxes, sprintf('[%d/%d] Sample %s: select %s', ...
            sampleIndex, numel(samples), sample.Name, firstPrompt), 'Interpreter', 'none');
        title(layout, sprintf('%s | Blue downward triangles: minima; red upward triangles: maxima\n%s', ...
            mineralChoice, methodCitation), 'Interpreter', 'none', 'FontSize', 11);

        %% Hematite only: saved minimum wavelengths in sample order.
        if strcmp(mineralChoice, 'Hematite')
            wavelengthAxes = nexttile(layout, 5);
            set(wavelengthAxes, 'Tag', 'HematiteMinimumAxes');
            est_plotHematiteMinima(wavelengthAxes, selectedRows);
        end

        %% Bottom: selected band intensity across samples
        if ~isClay
            amplitudeAxes = nexttile(layout,6);
        else
            amplitudeAxes = nexttile(layout,5,[1 2]);
        end
        est_plotSelectedAmplitudes(amplitudeAxes, selectedRows, amplitudeSymbol);
        if strcmp(mineralChoice, 'Hematite')
            set(amplitudeAxes, 'Tag', 'HematiteAmplitudeAxes');
        end
        % Fill the allocated wide upper area rather than letterboxing it.
        set(sampleAxes,'PlotBoxAspectRatioMode','auto','DataAspectRatioMode','auto');
        drawnow;

        [firstIndex, selectionCancelled] = est_waitForExtremumClick( ...
            figureHandle, sampleAxes, result, firstCandidates);
        if ~isgraphics(figureHandle), break; end
        if getappdata(figureHandle, 'StopRequested'), break; end
        if ~isempty(getappdata(figureHandle,'PendingSGWindow')), continue; end
        if selectionCancelled
            action = questdlg(sprintf('Selection of %s was not completed.', firstPrompt), ...
                'Current sample', 'Retry', 'Skip', 'Stop', 'Retry');
            if strcmp(action, 'Skip'), confirmed = true; continue; end
            if strcmp(action, 'Stop'), est_requestStop(figureHandle); break; end
            continue;
        end
        plot(sampleAxes, result.Wavelength(firstIndex), ...
            result.D2(firstIndex), 'o', 'MarkerSize', 13, ...
            'LineWidth', 2, 'Color', firstColor);
        title(sampleAxes, sprintf('[%d/%d] Sample %s: select %s', ...
            sampleIndex, numel(samples), sample.Name, secondPrompt), 'Interpreter', 'none');
        drawnow;
        [secondIndex, selectionCancelled] = est_waitForExtremumClick( ...
            figureHandle, sampleAxes, result, secondCandidates);
        if ~isgraphics(figureHandle), break; end
        if getappdata(figureHandle, 'StopRequested'), break; end
        if ~isempty(getappdata(figureHandle,'PendingSGWindow')), continue; end
        if selectionCancelled, continue; end
        plot(sampleAxes, result.Wavelength(secondIndex), ...
            result.D2(secondIndex), 'o', 'MarkerSize', 13, ...
            'LineWidth', 2, 'Color', secondColor);
        % Click order changes only for chlorite. Stored columns and A stay fixed.
        if any(strcmp(mineralChoice, {'Chlorite','2:1 clay minerals'}))
            selectedPeakIndex = firstIndex; selectedValleyIndex = secondIndex;
        else
            selectedValleyIndex = firstIndex; selectedPeakIndex = secondIndex;
        end

        valleyPosition = result.Wavelength(selectedValleyIndex);
        peakPosition = result.Wavelength(selectedPeakIndex);
        amplitude = result.D2(selectedPeakIndex)-result.D2(selectedValleyIndex);
        title(sampleAxes, sprintf('%s: minimum %.1f nm, maximum %.1f nm, amplitude %.6E', ...
            sample.Name, valleyPosition, peakPosition, amplitude), ...
            'Interpreter', 'none');
        drawnow;

        action = questdlg(sprintf(['Sample: %s\nMinimum: %.1f nm\nMaximum: %.1f nm', ...
            '\nMaximum minus minimum: %.6E'], sample.Name, valleyPosition, ...
            peakPosition, amplitude), 'Confirm selection', ...
            'Save and next', 'Reselect', 'Skip', 'Save and next');
        if strcmp(action, 'Save and next')
            est_recordSGSettings(outputFile,mineralSheetName,sample.Name,derivativeWindow,polynomialOrder,true);
            selectedRows = getappdata(figureHandle, 'SelectedRows');
            selectedRows(end+1, :) = ...
                {sample.Name, valleyPosition, peakPosition, amplitude}; %#ok<AGROW>
            selectedRows = est_sortSelectionRows(selectedRows);
            setappdata(figureHandle, 'SelectedRows', selectedRows);
            est_saveSelections(outputFile, mineralSheetName, selectedRows, ...
                amplitudeSymbol);
            if strcmp(mineralChoice, 'Hematite')
                est_refreshHematitePanels(figureHandle, selectedRows, amplitudeSymbol);
                drawnow;
            end
            confirmed = true;
        elseif strcmp(action, 'Skip') || isempty(action)
            confirmed = true;
        end

    end
end

%% Save the final Excel summary
if isgraphics(figureHandle)
    selectedRows = getappdata(figureHandle, 'SelectedRows');
elseif isfile(outputFile)
    % Confirmed selections and review edits were already written to disk.
    selectedRows = est_readExistingSelections(outputFile,mineralSheetName);
end
selectedRows = est_sortSelectionRows(selectedRows);
if isempty(selectedRows)
    if isgraphics(figureHandle), delete(figureHandle); end
    message = sprintf(['No mineral measurements were selected or saved.\n', ...
        'Processing failures: %d; missing peak/valley pairs: %d.\n', ...
        'Check the Command Window warnings and input wavelength range.\n', ...
        'Required display band for %s: %.0f-%.0f nm.\n', ...
        'Any workbook already created may contain settings only.'], ...
        processingFailures,missingPairs,mineralChoice,displayRange(1),displayRange(2));
    fprintf('\n%s\n',message);
    uiwait(warndlg(message,'No measurements saved','modal'));
    return;
end
est_saveSelections(outputFile, mineralSheetName, selectedRows, amplitudeSymbol);
fprintf('\nSelection complete: %d samples saved.\nOutput: %s\n', ...
    size(selectedRows, 1), outputFile);
uiwait(msgbox(sprintf('Processing complete.\nResults saved to:\n%s', outputFile), ...
    'Results saved', 'modal'));

end

%% ======================== Local functions =========================
function samples = est_collectAllSamples(inputFolder, outputFile)
    extensions = {'*.csv','*.txt','*.asc','*.dat','*.xlsx','*.xls'};
    files = [];
    for k = 1:numel(extensions)
        files = [files; dir(fullfile(inputFolder, extensions{k}))]; %#ok<AGROW>
    end
    samples = struct('Name', {}, 'Wavelength', {}, 'Reflectance', {});
    usedNames = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for fileIndex = 1:numel(files)
        inputFile = fullfile(files(fileIndex).folder, files(fileIndex).name);
        if startsWith(files(fileIndex).name, '.') || ...
                startsWith(files(fileIndex).name, '~$') || ...
                isLegacyResultFile(files(fileIndex).name) || ...
                startsWith(files(fileIndex).name, ...
                    {'ZLSpectra_DIY_','ZLSpectra_Advanced_','ZLSpectra_Configurable_','ZLSpectra_REL_'}, ...
                    'IgnoreCase',true) || ...
                contains(files(fileIndex).name,'_interactive_selections','IgnoreCase',true) || ...
                strcmpi(inputFile, outputFile)
            continue;
        end
        [~, baseName] = fileparts(files(fileIndex).name);
        try
            [headers, numericData, sampleCount] = est_readAllSamples(inputFile);
        catch ME
            warning('Skipping file %s: %s', files(fileIndex).name, ME.message);
            continue;
        end
        for sampleIndex = 1:sampleCount
            wavelengthColumn = 2*sampleIndex-1;
            reflectanceColumn = 2*sampleIndex;
            if sampleCount == 1
                sampleName = baseName;
            else
                sampleName = est_sampleValueToText(headers{wavelengthColumn});
                if isempty(sampleName)
                    sampleName = sprintf('%s_sample_%d', baseName, sampleIndex);
                end
            end
            sampleName = est_makeUniqueName(sampleName, usedNames);
            valid = isfinite(numericData(:, wavelengthColumn)) & ...
                isfinite(numericData(:, reflectanceColumn));
            if nnz(valid) < 50, continue; end
            samples(end+1).Name = sampleName; %#ok<AGROW>
            samples(end).Wavelength = numericData(valid, wavelengthColumn);
            samples(end).Reflectance = numericData(valid, reflectanceColumn);
        end
    end
end

function [headerFields, numericData, sampleCount] = est_readAllSamples(inputFile)
    [~, ~, extension] = fileparts(inputFile);
    if any(strcmpi(extension, {'.xlsx','.xls'}))
        allCells = readcell(inputFile);
        if isempty(allCells), error('The file is empty.'); end
        headerFields = allCells(1, :);
        numericData = readmatrix(inputFile, 'NumHeaderLines', 2);
    else
        fileID = fopen(inputFile, 'r');
        if fileID == -1, error('Cannot open the file.'); end
        cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
        firstLine = fgetl(fileID);
        if ~ischar(firstLine), error('The file has no first row.'); end
        headerFields = strsplit(firstLine, ',', 'CollapseDelimiters', false);
        if feof(fileID), error('The file has fewer than two rows.'); end
        fgetl(fileID);
        rows = {}; maximumColumns = 0;
        while ~feof(fileID)
            oneLine = fgetl(fileID);
            if ~ischar(oneLine) || isempty(strtrim(oneLine)), continue; end
            fields = strsplit(oneLine, ',', 'CollapseDelimiters', false);
            if numel(fields) < 2, fields = regexp(oneLine, '[;\t]', 'split'); end
            values = nan(1, numel(fields));
            for c = 1:numel(fields), values(c) = str2double(strtrim(fields{c})); end
            rows{end+1, 1} = values; %#ok<AGROW>
            maximumColumns = max(maximumColumns, numel(values));
        end
        numericData = nan(numel(rows), maximumColumns);
        for r = 1:numel(rows)
            numericData(r, 1:numel(rows{r})) = rows{r};
        end
    end
    nonempty = any(isfinite(numericData), 1);
    lastColumn = find(nonempty, 1, 'last');
    if isempty(lastColumn) || lastColumn < 2, error('No valid column pair found.'); end
    numericData = numericData(:, 1:lastColumn);
    if mod(size(numericData, 2), 2) ~= 0, numericData = numericData(:, 1:end-1); end
    sampleCount = size(numericData, 2)/2;
end

function samples = est_sortSamplesByNumber(samples)
    if numel(samples) < 2, return; end
    numbers = inf(numel(samples), 1);
    for k = 1:numel(samples)
        token = regexp(samples(k).Name, '[+-]?(?:\d+\.?\d*|\.\d+)', ...
            'match', 'once');
        if ~isempty(token), numbers(k) = str2double(token); end
    end
    original = (1:numel(samples))';
    [~, order] = sortrows([isinf(numbers), numbers, original], [1 2 3]);
    samples = samples(order);
end

function name = est_makeUniqueName(name, usedNames)
    name = strtrim(char(name));
    if isempty(name), name = 'Unnamed_sample'; end
    key = lower(name);
    if isKey(usedNames, key)
        usedNames(key) = usedNames(key)+1;
        name = sprintf('%s_%d', name, usedNames(key));
    else
        usedNames(key) = 1;
    end
end

function textValue = est_sampleValueToText(value)
    if isnumeric(value) && isscalar(value) && isfinite(value)
        textValue = num2str(value, '%.15g');
    elseif ischar(value) || isstring(value)
        textValue = strtrim(char(string(value)));
        if strcmpi(textValue, '<missing>'), textValue = ''; end
    else
        textValue = '';
    end
end

function [gridWavelength, gridReflectance] = est_makeOneNmGrid(wavelength, reflectance)
    [wavelength, order] = sort(wavelength(:), 'ascend');
    reflectance = reflectance(order);
    [uniqueWavelength, ~, groups] = unique(wavelength);
    uniqueReflectance = accumarray(groups, reflectance, [], @mean);
    gridWavelength = (ceil(min(uniqueWavelength)):floor(max(uniqueWavelength))).';
    gridReflectance = interp1(uniqueWavelength, uniqueReflectance, ...
        gridWavelength, 'linear');
    valid = isfinite(gridReflectance);
    gridWavelength = gridWavelength(valid);
    gridReflectance = gridReflectance(valid);
end

function [gridWavelength, gridReflectance] = est_makeProcessingGrid( ...
        wavelength, reflectance, method, analysisRange)
    wavelength = wavelength(:);
    reflectance = reflectance(:);
    finite = isfinite(wavelength) & isfinite(reflectance);
    wavelength = wavelength(finite); reflectance = reflectance(finite);
    [wavelength, order] = sort(wavelength, 'ascend');
    reflectance = reflectance(order);
    if strcmp(method, 'clayTwoStageSG')
        [wavelength, ~, group] = unique(wavelength);
        reflectance = accumarray(group, reflectance, [], @mean);
    end
    [wavelength, uniqueIndex] = unique(wavelength, 'stable');
    reflectance = reflectance(uniqueIndex);
    use = wavelength > analysisRange(1) & wavelength <= analysisRange(2);
    wavelength = wavelength(use);
    reflectance = reflectance(use);
    if numel(wavelength) < 60
        error('Fewer than 60 valid points between %.0f and %.0f nm.', ...
            analysisRange(1), analysisRange(2));
    end

    [gridWavelength, gridReflectance] = est_makeOneNmGrid( ...
        wavelength, reflectance);
end

function result = est_calculateSpectrumD2(wavelength, reflectance, method, ...
        smoothWindow, derivativeWindow, order, validRange)
    if strcmp(method, 'clayTwoStageSG')
        result = est_calculateClayTwoStageSG(wavelength, reflectance, ...
            derivativeWindow, order, validRange);
    else
        result = est_calculateD2(wavelength, reflectance, smoothWindow, ...
            derivativeWindow, order, validRange);
    end
end

function result = est_calculateClayTwoStageSG(wavelength, reflectance, window, order, validRange)
% Normalize R, smooth with fixed 5-point/order-2 SG, then K-M and SG D2.
    wavelength = wavelength(:); reflectance = reflectance(:);
    if numel(wavelength) ~= numel(reflectance) || numel(wavelength) < window+4
        error('Insufficient valid wavelength-reflectance pairs for the chosen SG window.');
    end
    if mod(window,2) ~= 1 || window ~= fix(window) || order ~= fix(order) ...
            || order < 2 || window <= order
        error('SG requires an odd window greater than the polynomial order (>= 2).');
    end
    if any(~isfinite(wavelength)) || any(~isfinite(reflectance)) ...
            || any(reflectance <= 0) || any(reflectance > 100)
        error('Reflectance must be finite, positive, and in the 0-1 or 0-100 range.');
    end
    if any(reflectance > 1), reflectance = reflectance/100; end
    if any(abs(diff(wavelength)-1) > 1e-8)
        error('Clay two-stage SG processing requires a uniform 1 nm grid.');
    end
    smoothCoefficient = est_sgCoefficients(5, 2, 0, 1);
    reflectance = conv(reflectance, fliplr(smoothCoefficient), 'valid');
    wavelength = wavelength(3:end-2);
    if any(~isfinite(reflectance)) || any(reflectance <= 0)
        error('Smoothed reflectance must be finite and positive for K-M transformation.');
    end
    FR = (1-reflectance).^2./(2*reflectance);
    coefficient = est_sgCoefficients(window, order, 2, 1);
    d2 = conv(FR, fliplr(coefficient), 'valid');
    half = (window-1)/2;
    grid = wavelength(half+1:end-half);
    [indices, types] = est_allExtrema(d2);
    inRange = grid(indices) >= validRange(1) & grid(indices) <= validRange(2);
    result.Wavelength = grid;
    result.D2 = d2;
    result.ExtremaIndex = indices(inRange);
    result.ExtremaType = types(inRange);
end


function result = est_calculateD2(wavelength, reflectancePercent, ...
        smoothWindow, derivativeWindow, order, validRange)
    minimumPoints = smoothWindow+derivativeWindow;
    if numel(wavelength) < minimumPoints, error('Insufficient valid points.'); end
    smoothCoefficient = est_sgCoefficients(smoothWindow, order, 0, 1);
    smoothReflectance = conv(reflectancePercent(:), ...
        fliplr(smoothCoefficient), 'valid')/100;
    smoothHalf = (smoothWindow-1)/2;
    smoothWavelength = wavelength(smoothHalf+1:end-smoothHalf);
    if any(smoothReflectance <= 0), error('Smoothed reflectance is non-positive.'); end
    FR = (1-smoothReflectance).^2./(2*smoothReflectance);
    derivativeCoefficient = est_sgCoefficients(derivativeWindow, order, 2, 1);
    d2 = conv(FR, fliplr(derivativeCoefficient), 'valid');
    derivativeHalf = (derivativeWindow-1)/2;
    d2Wavelength = smoothWavelength(derivativeHalf+1:end-derivativeHalf);
    [indices, types] = est_allExtrema(d2);
    inRange = d2Wavelength(indices) >= validRange(1) & ...
        d2Wavelength(indices) <= validRange(2);
    result.Wavelength = d2Wavelength;
    result.D2 = d2;
    result.ExtremaIndex = indices(inRange);
    result.ExtremaType = types(inRange);
end


function coefficient = est_sgCoefficients(window, order, derivative, spacing)
    halfWindow = (window-1)/2;
    x = (-halfWindow:halfWindow).';
    design = zeros(window, order+1);
    for power = 0:order, design(:, power+1) = x.^power; end
    selector = zeros(1, order+1);
    selector(derivative+1) = factorial(derivative)/spacing^derivative;
    coefficient = selector/(design.'*design)*design.';
end

function [indices, types] = est_allExtrema(y)
    y = y(:);
    minimumIndices = find(y(2:end-1) < y(1:end-2) & ...
        y(2:end-1) <= y(3:end))+1;
    maximumIndices = find(y(2:end-1) > y(1:end-2) & ...
        y(2:end-1) >= y(3:end))+1;
    indices = [minimumIndices; maximumIndices];
    types = [repmat({'mini'}, numel(minimumIndices), 1); ...
        repmat({'max'}, numel(maximumIndices), 1)];
    [indices, order] = sort(indices);
    types = types(order);
end

function est_plotReferenceExtrema(ax, result)
    isValley = strcmp(result.ExtremaType, 'mini');
    isPeak = strcmp(result.ExtremaType, 'max');
    valleys = result.ExtremaIndex(isValley);
    peaks = result.ExtremaIndex(isPeak);
    plot(ax, result.Wavelength(valleys), result.D2(valleys), 'v', ...
        'LineStyle', 'none', 'MarkerSize', 5, 'MarkerEdgeColor', ...
        [0.1 0.35 0.85], 'MarkerFaceColor', 'none');
    plot(ax, result.Wavelength(peaks), result.D2(peaks), '^', ...
        'LineStyle', 'none', 'MarkerSize', 5, 'MarkerEdgeColor', ...
        [0.85 0.2 0.1], 'MarkerFaceColor', 'none');
end

function est_drawLiteratureReference(ax, valleyNm, peakNm, valleyRange, peakRange, citation)
    if all(isfinite(valleyRange))
        est_shadeReferenceRange(ax, valleyRange, [0.50 0.70 1.00], ...
            sprintf('Minimum %.0f-%.0f nm', valleyRange), [0.15 0.35 0.75]);
    end
    if all(isfinite(peakRange))
        est_shadeReferenceRange(ax, peakRange, [1.00 0.60 0.55], ...
            sprintf('Maximum %.0f-%.0f nm', peakRange), [0.75 0.15 0.10]);
    end
    if isfinite(valleyNm)
    xline(ax, valleyNm, '--', sprintf('Minimum ~%.0f nm', valleyNm), ...
        'Color', [0 0.2 0.8], 'LineWidth', 1.2, ...
        'LabelVerticalAlignment', 'top', ...
        'LabelHorizontalAlignment', 'left', ...
        'LabelOrientation', 'horizontal');
    end
    if isfinite(peakNm)
    xline(ax, peakNm, '--', sprintf('Maximum ~%.0f nm', peakNm), ...
        'Color', [0.8 0.1 0], 'LineWidth', 1.2, ...
        'LabelVerticalAlignment', 'bottom', ...
        'LabelHorizontalAlignment', 'right', ...
        'LabelOrientation', 'horizontal');
    end
    text(ax, 0.01, 0.98, ['Literature reference: ', citation], ...
        'Units', 'normalized', 'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'top', 'FontSize', 9, ...
        'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
end

function est_shadeReferenceRange(ax, range, faceColor, label, textColor)
% The shaded background must not intercept clicks on spectral candidates.
    limits = ylim(ax);
    background = patch(ax, [range(1) range(2) range(2) range(1)], ...
        [limits(1) limits(1) limits(2) limits(2)], faceColor, ...
        'FaceAlpha',0.22,'EdgeColor','none','HitTest','off', ...
        'PickableParts','none','HandleVisibility','off');
    uistack(background,'bottom');
    ylim(ax,limits);
    text(ax,mean(range),limits(1)+0.07*diff(limits),label, ...
        'Color',textColor,'FontSize',9,'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom','Clipping','on','HitTest','off', ...
        'PickableParts','none','Interpreter','none');
end

function est_drawHematiteLiteratureLines(ax, valleyNm, peakNm, citation)
    % Show only two nominal literature positions on the hematite sample.
    xline(ax, valleyNm, '--', sprintf('Literature minimum ~%.0f nm', valleyNm), ...
        'Color', [0 0.2 0.8], 'LineWidth', 1.25, ...
        'LabelVerticalAlignment', 'top', ...
        'LabelHorizontalAlignment', 'left', ...
        'LabelOrientation', 'horizontal');
    xline(ax, peakNm, '--', sprintf('Literature maximum ~%.0f nm', peakNm), ...
        'Color', [0.8 0.1 0], 'LineWidth', 1.25, ...
        'LabelVerticalAlignment', 'bottom', ...
        'LabelHorizontalAlignment', 'right', ...
        'LabelOrientation', 'horizontal');
    text(ax, 0.01, 0.02, ['Literature reference: ', citation], ...
        'Units', 'normalized', 'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'bottom', 'FontSize', 8, ...
        'BackgroundColor','w','Margin',1,'HitTest','off', ...
        'PickableParts','none','HandleVisibility','off', ...
        'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
end

function est_createStopButton(figureHandle)
    uicontrol(figureHandle, 'Style', 'pushbutton', ...
        'String', 'Stop and save', 'Units', 'normalized', ...
        'Position', [0.84 0.955 0.14 0.035], 'FontSize', 11, ...
        'FontWeight', 'bold', 'ForegroundColor', [0.75 0.05 0.05], ...
        'Callback', @(~,~) est_requestStop(figureHandle));
end

function est_requestStop(figureHandle)
    if isgraphics(figureHandle)
        setappdata(figureHandle, 'StopRequested', true);
        drawnow;
    end
end

function [selectedIndex, cancelled] = est_waitForExtremumClick( ...
        figureHandle, ax, result, candidateIndices)
    selectedIndex = [];
    cancelled = true;
    while isgraphics(figureHandle)
        if getappdata(figureHandle, 'StopRequested'), return; end
        if ~isempty(getappdata(figureHandle,'PendingSGWindow')), return; end
        try
            % waitforbuttonpress uses the current figure. Explicitly target
            % the selection window after a review window has been opened.
            figure(figureHandle);
            keyWasPressed = waitforbuttonpress;
        catch ME
            % MATLAB throws when the window is deleted while waiting.
            if ~isgraphics(figureHandle), return; end
            if getappdata(figureHandle,'StopRequested'), return; end
            rethrow(ME);
        end
        if ~isgraphics(figureHandle) || ~isgraphics(ax), return; end
        if getappdata(figureHandle, 'StopRequested'), return; end
        if ~isempty(getappdata(figureHandle,'PendingSGWindow')), return; end
        if keyWasPressed
            key = get(figureHandle, 'CurrentCharacter');
            if ~isempty(key) && (lower(key) == 'q' || double(key) == 27)
                return;
            end
            continue;
        end
        if ~strcmp(get(figureHandle, 'SelectionType'), 'normal')
            return;
        end
        clickedObject = hittest(figureHandle);
        clickedAxes = ancestor(clickedObject, 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            continue;
        end
        point = get(ax, 'CurrentPoint');
        clickedX = point(1, 1);
        [~, nearest] = min(abs( ...
            result.Wavelength(candidateIndices)-clickedX));
        selectedIndex = candidateIndices(nearest);
        cancelled = false;
        return;
    end
end

function result = est_filterClayGroupExtrema(result)
% Separate published candidate intervals: left maximum, right minimum.
    wavelength = result.Wavelength(result.ExtremaIndex);
    isMinimum = strcmp(result.ExtremaType,'mini');
    isMaximum = strcmp(result.ExtremaType,'max');
    keep = (isMinimum & wavelength >= 1900 & wavelength <= 1925) | ...
           (isMaximum & wavelength >= 1870 & wavelength <= 1895);
    result.ExtremaIndex = result.ExtremaIndex(keep);
    result.ExtremaType = result.ExtremaType(keep);
end

function [compatible, reason] = est_clayResumeCompatible( ...
        outputFile, sheetName, expectedSettings, inputFolder)
    compatible = false; reason = '';
    try
        cells = readcell(outputFile, 'Sheet', [sheetName '_Reference']);
    catch
        reason = 'No readable processing-parameter sheet was found.';
        return;
    end
    if size(cells,2) < 2
        reason = 'The processing-parameter sheet is incomplete.';
        return;
    end
    keys = cellfun(@est_sampleValueToText, cells(:,1), 'UniformOutput',false);
    for k = 1:size(expectedSettings,1)
        key = expectedSettings{k,1};
        row = find(strcmp(keys,key),1);
        if isempty(row)
            reason = ['Missing saved parameter: ' key]; return;
        end
        expected = expectedSettings{k,2}; actual = cells{row,2};
        if isnumeric(expected)
            same = isequal(est_numericCellValue(actual),expected);
        else
            same = strcmp(est_sampleValueToText(actual),expected);
        end
        if ~same
            reason = ['Different saved parameter: ' key]; return;
        end
    end
    % Older workbooks did not record input-folder paths; keep them readable.
    row = find(strcmp(keys,'Input_folder'),1);
    if ~isempty(row) && ~strcmp(est_sampleValueToText(cells{row,2}),inputFolder)
        reason = 'The saved input folder differs from the selected folder.';
        return;
    end
    compatible = true;
end

function rows = est_readExistingSelections(outputFile, sheetName)
    rows = cell(0, 4);
    if ~isfile(outputFile), return; end
    try
        cells = readcell(outputFile, 'Sheet', sheetName);
    catch
        return;
    end
    if size(cells, 1) < 2 || size(cells, 2) < 4, return; end
    for rowIndex = 2:size(cells, 1)
        sampleName = est_sampleValueToText(cells{rowIndex, 1});
        valley = est_numericCellValue(cells{rowIndex, 2});
        peak = est_numericCellValue(cells{rowIndex, 3});
        amplitude = est_numericCellValue(cells{rowIndex, 4});
        if ~isempty(sampleName) && all(isfinite([valley peak amplitude]))
            rows(end+1, :) = {sampleName, valley, peak, amplitude}; %#ok<AGROW>
        end
    end
    rows = est_sortSelectionRows(rows);
end

function value = est_numericCellValue(inputValue)
    if isnumeric(inputValue) && isscalar(inputValue)
        value = double(inputValue);
    else
        value = str2double(string(inputValue));
    end
end

function rows = est_sortSelectionRows(rows)
    if size(rows, 1) < 2, return; end
    names = string(rows(:, 1));
    numbers = inf(size(names));
    for rowIndex = 1:numel(names)
        token = regexp(char(names(rowIndex)), ...
            '[+-]?(?:\d+\.?\d*|\.\d+)', 'match', 'once');
        if ~isempty(token), numbers(rowIndex) = str2double(token); end
    end
    originalOrder = (1:numel(names)).';
    [~, order] = sortrows([isinf(numbers), numbers, originalOrder], [1 2 3]);
    rows = rows(order, :);
end

function est_saveSelections(outputFile, sheetName, rows, amplitudeSymbol)
    % Excel uses plain-text subscripts; plots retain MATLAB TeX notation.
    outputSymbol = strrep(strrep(amplitudeSymbol, '{', ''), '}', '');
    headers = {'Sample ID', 'Minimum (nm)', 'Maximum (nm)', ...
        sprintf('%s (D2 max - D2 min)', outputSymbol)};
    writecell([headers; rows], outputFile, 'Sheet', sheetName);
end

function est_plotSelectedAmplitudes(ax, rows, amplitudeSymbol)
    cla(ax);
    if isempty(rows)
        axis(ax, 'off');
        text(ax, 0.5, 0.5, sprintf('No saved %s band intensities yet', ...
            amplitudeSymbol), 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'Color', [0.4 0.4 0.4]);
        return;
    end
    rows = est_sortSelectionRows(rows);
    sampleNames = string(rows(:, 1));
    amplitudes = cell2mat(rows(:, 4));
    x = 1:numel(amplitudes);
    trendLine = plot(ax, x, amplitudes, '-o', 'LineWidth', 1.1, ...
        'MarkerSize', 5, 'MarkerFaceColor', [0.2 0.55 0.85], ...
        'Color', [0.1 0.35 0.7]);
    set(trendLine, 'HitTest', 'on', 'PickableParts', 'all', ...
        'ButtonDownFcn', @est_amplitudePointClicked);
    grid(ax, 'on');
    xlim(ax, [0.5 numel(x)+0.5]);
    xticks(ax, x);
    xticklabels(ax, sampleNames);
    xtickangle(ax, 60);
    xlabel(ax, 'Sample ID (ascending order)');
    ylabel(ax, amplitudeSymbol, 'Interpreter', 'tex');
    title(ax, sprintf('Selected %s band intensities (%d samples; click a point to review/edit)', ...
        amplitudeSymbol, numel(amplitudes)));
end

function est_plotHematiteMinima(ax, rows)
    cla(ax);
    axis(ax, 'on');
    xlabel(ax, 'Sample ID (ascending order)');
    ylabel(ax, 'Selected minimum wavelength (nm)');
    title(ax, 'Hematite minimum wavelengths (click a point to review/edit)');
    grid(ax, 'on');
    if isempty(rows)
        text(ax, 0.5, 0.5, 'No saved hematite minimum wavelengths yet', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'Color', [0.4 0.4 0.4]);
        return;
    end
    rows = est_sortSelectionRows(rows);
    wavelengths = cell2mat(rows(:, 2));
    x = 1:size(rows, 1);
    trendLine = plot(ax, x, wavelengths, '-s', 'Color', [0.2 0.2 0.2], ...
        'LineWidth', 1.1, 'MarkerSize', 5, 'MarkerFaceColor', 'w');
    set(trendLine, 'HitTest', 'on', 'PickableParts', 'all', ...
        'ButtonDownFcn', @est_amplitudePointClicked);
    referenceLine = yline(ax, 550, '--', '550 nm', ...
        'Color', [0.55 0.55 0.55], 'LineWidth', 1.2);
    set(referenceLine, 'HitTest', 'off', 'PickableParts', 'none');
    wavelengthLimits = [min([wavelengths(:); 550]), max([wavelengths(:); 550])];
    wavelengthPadding = max(1, 0.08 * diff(wavelengthLimits));
    ylim(ax, wavelengthLimits + [-wavelengthPadding wavelengthPadding]);
    grid(ax, 'on');
    xlim(ax, [0.5 numel(x)+0.5]);
    xticks(ax, x);
    xticklabels(ax, string(rows(:, 1)));
    xtickangle(ax, 60);
    xlabel(ax, 'Sample ID (ascending order)');
    ylabel(ax, 'Selected minimum wavelength (nm)');
    title(ax, sprintf('Hematite minimum wavelengths (%d samples; click a point to review/edit)', ...
        numel(x)));
    set(ax, 'Tag', 'HematiteMinimumAxes');
end

function est_refreshHematitePanels(figureHandle, rows, amplitudeSymbol)
    minimumAxes = findobj(figureHandle, 'Type', 'axes', 'Tag', 'HematiteMinimumAxes');
    amplitudeAxes = findobj(figureHandle, 'Type', 'axes', 'Tag', 'HematiteAmplitudeAxes');
    if ~isempty(minimumAxes)
        est_plotHematiteMinima(minimumAxes(1), rows);
    end
    if ~isempty(amplitudeAxes)
        % The initial empty amplitude panel disables its axes.
        axis(amplitudeAxes(1), 'on');
        est_plotSelectedAmplitudes(amplitudeAxes(1), rows, amplitudeSymbol);
        set(amplitudeAxes(1), 'Tag', 'HematiteAmplitudeAxes');
    end
end

function est_amplitudePointClicked(lineHandle, ~)
    ax = ancestor(lineHandle, 'axes');
    figureHandle = ancestor(ax, 'figure');
    if isempty(figureHandle) || ~isappdata(figureHandle, 'EditContext'), return; end
    rows = getappdata(figureHandle, 'SelectedRows');
    if isempty(rows), return; end
    rows = est_sortSelectionRows(rows);
    point = get(ax, 'CurrentPoint');
    [~, rowIndex] = min(abs((1:size(rows, 1))-point(1, 1)));
    sampleName = char(string(rows{rowIndex, 1}));
    action = questdlg(sprintf('Sample: %s\nChoose an action.', sampleName), ...
        'Review or edit selection', 'Review', 'Edit', 'Cancel', 'Review');
    if isempty(action) || strcmp(action, 'Cancel'), return; end
    context = getappdata(figureHandle, 'EditContext');
    [newRow, changed] = est_showOrEditSavedSelection( ...
        rows(rowIndex, :), context, strcmp(action, 'Edit'));
    if changed
        rows(rowIndex, :) = newRow;
        rows = est_sortSelectionRows(rows);
        setappdata(figureHandle, 'SelectedRows', rows);
        est_saveSelections(context.OutputFile, context.SheetName, rows, ...
            context.AmplitudeSymbol);
        if strcmp(context.SheetName, 'Hematite')
            est_refreshHematitePanels(figureHandle, rows, context.AmplitudeSymbol);
        else
            est_plotSelectedAmplitudes(ax, rows, context.AmplitudeSymbol);
        end
        drawnow;
    end
end

function [newRow, changed] = est_showOrEditSavedSelection(oldRow, context, doEdit)
    newRow = oldRow;
    changed = false;
    sampleName = char(string(oldRow{1}));
    try
        parameterRows = readcell(context.OutputFile,'Sheet','SG_parameters');
        for parameterIndex = 2:size(parameterRows,1)
            if strcmp(char(string(parameterRows{parameterIndex,1})),context.SheetName) && ...
                    strcmp(char(string(parameterRows{parameterIndex,2})),sampleName)
                context.DerivativeWindow = parameterRows{parameterIndex,3};
                context.PolynomialOrder = parameterRows{parameterIndex,4};
                context.MethodCitation = sprintf('Saved SG D2: %d points, order %d',context.DerivativeWindow,context.PolynomialOrder);
                break;
            end
        end
    catch
        % Legacy workbook: retain its original/default context.
    end
    sampleNames = string({context.AllSamples.Name});
    sampleIndex = find(sampleNames == string(sampleName), 1);
    if isempty(sampleIndex)
        warning('Raw spectrum for sample %s was not found; cannot review.', sampleName);
        return;
    end
    sample = context.AllSamples(sampleIndex);
    try
        [wavelength, reflectance] = est_makeProcessingGrid( ...
            sample.Wavelength, sample.Reflectance, ...
            context.ProcessingMethod, context.AnalysisRange);
        result = est_calculateSpectrumD2(wavelength, reflectance, ...
            context.ProcessingMethod, context.PreSmoothWindow, ...
            context.DerivativeWindow, context.PolynomialOrder, ...
            context.DisplayRange);
    catch ME
        warning('Failed to reprocess sample %s: %s', sampleName, ME.message);
        return;
    end
    if strcmp(context.SheetName,'Clay_2to1')
        result = est_filterClayGroupExtrema(result);
    end
    isValley = strcmp(result.ExtremaType, 'mini');
    isPeak = strcmp(result.ExtremaType, 'max');
    valleyIndices = result.ExtremaIndex(isValley);
    peakIndices = result.ExtremaIndex(isPeak);
    if isempty(valleyIndices) || isempty(peakIndices)
        warning('No complete minimum/maximum pair in the displayed band for %s.', sampleName);
        return;
    end
    reviewFigure = figure('Name', ['Review sample ', sampleName], ...
        'Color', 'w', 'Position', [180 120 1100 620], 'NumberTitle', 'off');
    reviewAxes = axes(reviewFigure);
    plot(reviewAxes, result.Wavelength, result.D2, 'k-', 'LineWidth', 1.2);
    hold(reviewAxes, 'on');
    yline(reviewAxes, 0, ':', 'Color', [0.65 0.65 0.65]);
    plot(reviewAxes, result.Wavelength(valleyIndices), result.D2(valleyIndices), ...
        'v', 'LineStyle', 'none', 'MarkerFaceColor', [0.55 0.72 1], ...
        'MarkerEdgeColor', [0 0.25 0.8]);
    plot(reviewAxes, result.Wavelength(peakIndices), result.D2(peakIndices), ...
        '^', 'LineStyle', 'none', 'MarkerFaceColor', [1 0.65 0.5], ...
        'MarkerEdgeColor', [0.8 0.1 0]);
    [~, oldValleyNearest] = min(abs(result.Wavelength-oldRow{2}));
    [~, oldPeakNearest] = min(abs(result.Wavelength-oldRow{3}));
    plot(reviewAxes, result.Wavelength(oldValleyNearest), ...
        result.D2(oldValleyNearest), 'bo', 'MarkerSize', 13, 'LineWidth', 2);
    plot(reviewAxes, result.Wavelength(oldPeakNearest), ...
        result.D2(oldPeakNearest), 'ro', 'MarkerSize', 13, 'LineWidth', 2);
    if strcmp(context.SheetName, 'Hematite')
        est_drawHematiteLiteratureLines(reviewAxes, ...
            context.LiteratureValleyNm, context.LiteraturePeakNm, ...
            context.BandCitation);
    else
        est_drawLiteratureReference(reviewAxes, context.LiteratureValleyNm, ...
            context.LiteraturePeakNm, context.LiteratureValleyRange, ...
            context.LiteraturePeakRange, context.BandCitation);
    end
    xlim(reviewAxes, context.DisplayRange); grid(reviewAxes, 'on');
    xlabel(reviewAxes, 'Wavelength (nm)');
    ylabel(reviewAxes, 'd^2F(R)/d\lambda^2');
    title(reviewAxes, sprintf('%s: saved minimum %.1f nm, maximum %.1f nm, %s = %.6E | %s', ...
        sampleName, oldRow{2}, oldRow{3}, context.AmplitudeSymbol, ...
        oldRow{4}, context.MethodCitation), ...
        'Interpreter', 'none');
    if ~doEdit, return; end
    if any(strcmp(context.SheetName, {'Chlorite','Clay_2to1'}))
        candidates = {peakIndices, valleyIndices};
        prompts = {'maximum (red)', 'minimum (blue)'};
        colors = {'r', 'b'};
    else
        candidates = {valleyIndices, peakIndices};
        prompts = {'minimum (blue)', 'maximum (red)'};
        colors = {'b', 'r'};
    end
    editedIndices = zeros(1,2);
    for selectionStep = 1:2
        title(reviewAxes, sprintf('%s: select a new %s', ...
            sampleName, prompts{selectionStep}), 'Interpreter', 'none');
        axes(reviewAxes); %#ok<LAXES>
        [clickedX, ~, button] = ginput(1);
        if isempty(clickedX) || button ~= 1 || ~isgraphics(reviewFigure)
            if isgraphics(reviewFigure), close(reviewFigure); end
            return;
        end
        pool = candidates{selectionStep};
        [~, nearest] = min(abs(result.Wavelength(pool)-clickedX));
        editedIndices(selectionStep) = pool(nearest);
        plot(reviewAxes, result.Wavelength(pool(nearest)), ...
            result.D2(pool(nearest)), 's', 'Color', colors{selectionStep}, ...
            'MarkerSize', 13, 'LineWidth', 2);
    end
    if any(strcmp(context.SheetName, {'Chlorite','Clay_2to1'}))
        newPeakIndex = editedIndices(1); newValleyIndex = editedIndices(2);
    else
        newValleyIndex = editedIndices(1); newPeakIndex = editedIndices(2);
    end
    valleyPosition = result.Wavelength(newValleyIndex);
    peakPosition = result.Wavelength(newPeakIndex);
    amplitude = result.D2(newPeakIndex)-result.D2(newValleyIndex);
    answer = questdlg(sprintf('Sample: %s\nNew minimum: %.1f nm\nNew maximum: %.1f nm\n%s: %.6E', ...
        sampleName, valleyPosition, peakPosition, ...
        context.AmplitudeSymbol, amplitude), 'Confirm edit', ...
        'Overwrite', 'Cancel', 'Overwrite');
    if strcmp(answer, 'Overwrite')
        newRow = {sampleName, valleyPosition, peakPosition, amplitude};
        changed = true;
    end
    if isgraphics(reviewFigure), close(reviewFigure); end
end

function est_labelExtrema(ax, result, indices, prefix, color)
    if isempty(indices), return; end
    visibleMask = result.Wavelength >= ax.XLim(1) & result.Wavelength <= ax.XLim(2);
    visibleValues = result.D2(visibleMask);
    if isempty(visibleValues), return; end
    offset = 0.02*max(max(visibleValues)-min(visibleValues), eps);
    for k = 1:numel(indices)
        index = indices(k);
        if strcmp(prefix, 'Min'), yText = result.D2(index)-offset; valign = 'top';
        else, yText = result.D2(index)+offset; valign = 'bottom'; end
        text(ax, result.Wavelength(index), yText, ...
            sprintf('%s %.0f', prefix, result.Wavelength(index)), ...
            'FontSize', 7, 'Rotation', 60, 'Color', color, ...
            'VerticalAlignment', valign, 'Clipping', 'on');
    end
end

function [wavelength, reflectance] = est_embeddedReferenceSpectrum(mineralChoice)
    % Source spectra sampled at 0.5 nm in the script's analysis band.
    % Hematite: CTK.csv; goethite: ZTK.csv; gypsum: SG.csv;
    % CaCO3: 0%.csv. Reflectance values retain their original %R precision.
    switch mineralChoice
        case 'Hematite'
            [firstNm, lastNm, reflectance] = est_embeddedHematite();
        case 'Goethite'
            [firstNm, lastNm, reflectance] = est_embeddedGoethite();
        case 'Gypsum'
            [firstNm, lastNm, reflectance] = est_embeddedGypsum();
        case 'Calcium carbonate'
            [firstNm, lastNm, reflectance] = est_embeddedCalciumCarbonate();
        otherwise
            error('No embedded reference for %s.', mineralChoice);
    end
    wavelength = (firstNm:-0.5:lastNm).';
    if numel(wavelength) ~= numel(reflectance)
        error('Embedded reference point count is inconsistent for %s.', ...
            mineralChoice);
    end
end

function [firstNm, lastNm, reflectance] = est_embeddedHematite()
    firstNm = 900;
    lastNm = 380.5;
    reflectance = sscanf([ ...
        '24.70287323 24.75647163 24.61753464 24.66787148 24.51404572 24.61441231 24.48895836 24.52175522 24.36392021 24.39735603 24.36982918 24.25903893 24.33183861 24.20223618 24.3364563 24.38737297 24.22174263 24.19680786 24.21578217 24.14095306 24.11910057 24.11643219 24.00623322 24.03495407 23.96533966 23.93959999 23.87214661 23.94902039 23.96786308 23.87709999 23.89756775 23.8532238 23.7524128 23.83689117 23.72824287 23.75782967 23.7279911 23.79575539 23.71330643 23.69549942 23.59584045 23.65465736 23.64543915 23.64289665 23.62790298 23.6568222 23.67930984 23.60939026 23.57396507 23.61222649 23.62976074 23.44431305 23.5467453 23.51068687 23.50702477 23.45345879 23.50073814 23.43658829 23.45701408 23.38180733 23.33102989 23.367136 23.41908455 23.276577 23.26853371 23.41957474 23.27879333 23.25232315 23.41833878 23.37419891 ' ...
        '23.31772423 23.47341537 23.20442581 23.27651596 23.36453629 23.18676949 23.3224678 23.2341938 23.2511425 23.2947464 23.19079971 23.17518616 23.22979546 22.95915222 23.26836014 23.19627762 23.26163292 23.07916069 23.35516548 23.1859684 23.20171738 23.29406738 23.25636864 23.43579865 23.10012245 23.18764496 23.42127419 22.98843765 23.18034554 23.13242912 23.24482536 23.12877655 23.35293198 23.15750504 23.35338783 23.2158699 23.28592682 23.28536034 23.27321243 23.36217117 23.13743591 22.96901131 23.43682098 23.07892799 23.45892334 23.2427845 23.26793861 23.30002022 23.77993584 23.29073524 23.55601883 23.42238617 23.2265892 23.17988205 23.29731941 23.69522858 23.42022514 23.28209686 23.76380348 23.71590042 23.62240791 23.4770565 23.54912186 23.71336174 23.59976387 23.63542557 23.89749336 23.82872963 24.00180054 23.87332344 ' ...
        '23.49671364 23.75502014 23.57841682 23.77201271 23.51036453 23.93040276 23.80257607 23.8188858 23.88165665 23.98886871 23.7812748 24.22931862 23.76545906 24.20153999 24.07590103 24.22369003 23.79780579 23.8486824 24.13624001 23.9322567 23.90362358 24.03646278 23.92381096 24.00334549 24.28383255 24.40348625 24.5172081 24.51211739 24.301157 24.26982117 24.56092644 24.52944946 24.53422356 24.66750526 24.25152779 24.51059532 24.78563881 24.64428711 24.45809174 24.91747475 24.88973808 24.91918373 24.65977669 24.89541817 24.43482971 25.12350464 24.95092583 25.19354248 25.1934166 25.12374306 25.09902954 25.43093872 25.27249146 25.33678627 24.87445068 25.32848167 25.61036873 25.21817398 25.19998169 25.39500809 25.81260872 25.42092133 25.51887321 25.52162933 25.67360115 25.64413834 25.8474617 25.74463463 25.91410255 25.86145401 ' ...
        '25.93078995 26.06251144 25.82897568 26.08240509 26.00930977 26.12692451 26.14032364 26.16342545 26.37739182 26.31204987 26.22775078 26.28854179 26.40475082 26.49234009 26.50907135 26.60680962 26.59815216 26.6179657 26.69919777 26.85853767 26.90485954 26.86165047 26.88331604 26.9921627 26.99149513 27.06368256 27.11608124 27.15702629 27.17425919 27.32863426 27.32608414 27.43660545 27.39056587 27.446661 27.49885559 27.55106163 27.61946869 27.65680313 27.70702744 27.67337608 27.81076813 27.75297165 27.91137314 27.90651321 27.97907257 28.06536865 28.03635025 28.12798691 28.2190094 28.24815559 28.18902779 28.26851654 28.36499786 28.32041359 28.3695755 28.43428802 28.46156693 28.4833107 28.63906288 28.68735123 28.67386055 28.77505684 28.69770241 28.82370949 28.90481949 28.81887245 28.96262741 29.05176926 29.05698967 28.94451523 ' ...
        '29.10231018 29.13995361 29.16317368 29.14124489 29.19666672 29.24708748 29.19897652 29.2065258 29.22249413 29.26330185 29.38530731 29.40865707 29.38226509 29.44422722 29.33828545 29.43412399 29.45913124 29.42901039 29.4895134 29.50005531 29.52914238 29.53258514 29.42912865 29.54892159 29.51484299 29.49007988 29.54085159 29.5366497 29.54958344 29.54792595 29.55768776 29.48881721 29.46916199 29.54045868 29.57894897 29.43331337 29.4752121 29.42100525 29.47489357 29.41863823 29.37709427 29.37299538 29.32007027 29.28800583 29.29958916 29.30406952 29.20453644 29.1964016 29.12699318 29.10019684 29.04820442 29.06850243 28.98977661 28.92440605 28.90543556 28.95001793 28.83838654 28.72801208 28.75482368 28.71972656 28.60348129 28.58043861 28.4783535 28.46051216 28.47104073 28.41166496 28.3067646 28.22634888 28.15480232 28.14324188 ' ...
        '28.03557777 27.98447609 28.0036335 27.84694481 27.84435463 27.7220211 27.65496635 27.61305046 27.56461525 27.45861435 27.41352272 27.30615425 27.29047012 27.12701225 27.10423851 26.99989128 26.93814278 26.85750961 26.87214851 26.77022743 26.66820526 26.55229187 26.46763611 26.38001442 26.36061287 26.29678917 26.17043877 26.04348755 26.04297447 25.9009304 25.82971191 25.7671299 25.70516396 25.60012436 25.53471565 25.49717331 25.37099648 25.307024 25.25432205 25.14987373 25.08025551 25.01608467 24.91686058 24.84186745 24.77034569 24.6946125 24.62022972 24.51049995 24.47821426 24.35871696 24.32492638 24.27139091 24.18205643 24.13025284 24.0193882 23.91651917 23.89839935 23.81183434 23.70826721 23.63870621 23.61154938 23.50457573 23.43719864 23.39777946 23.30584145 23.25465202 23.18940926 23.09609413 23.05559349 22.98728561 ' ...
        '22.95797539 22.82702637 22.76378632 22.71450424 22.65385246 22.61733818 22.5394516 22.47649193 22.40917587 22.37208176 22.29034233 22.24032021 22.22132492 22.10679436 22.04545021 21.99671745 21.95622063 21.89770126 21.85521317 21.81960487 21.75055313 21.68808556 21.61988258 21.6002636 21.55040169 21.47543144 21.41479492 21.39458656 21.33394241 21.29336739 21.21986389 21.1605072 21.1397686 21.11380386 21.054533 21.00833702 20.96291542 20.92734337 20.88474655 20.8026104 20.78384209 20.71969986 20.69417763 20.66480064 20.59611893 20.57845688 20.56419373 20.50695038 20.46385193 20.38823509 20.3690834 20.34454346 20.29471016 20.25895309 20.24615479 20.22075272 20.18432808 20.11657524 20.11092377 20.06635666 20.03527069 19.99232864 19.99186516 19.96084404 19.90463829 19.87508774 19.83976936 19.79467392 19.75909805 19.75512505 ' ...
        '19.71560478 19.72569084 19.64905167 19.62006187 19.59745789 19.57916451 19.53573227 19.55407715 19.52651405 19.46754646 19.4703083 19.4321003 19.39423752 19.36366653 19.376791 19.36732292 19.32211685 19.28675842 19.27378654 19.23163605 19.16864014 19.18991661 19.17878151 19.15414619 19.16042709 19.11149979 19.08564377 19.08691025 19.04916763 19.01893806 19.0368824 18.99226761 18.98836708 18.9763279 18.90756035 18.91841888 18.90920258 18.87845612 18.88489151 18.83378029 18.82885933 18.82068825 18.79417038 18.7971611 18.75392342 18.73678589 18.72120857 18.72606277 18.67054939 18.66892052 18.66798973 18.59886551 18.59449005 18.59186172 18.54160881 18.57933617 18.53889084 18.50380325 18.46901894 18.43156624 18.40854836 18.41804504 18.36115074 18.35925484 18.3506546 18.32807541 18.30035019 18.27141762 18.2442379 18.2112236 ' ...
        '18.20610046 18.15664291 18.14754105 18.12163544 18.09103966 18.0401268 18.02083397 17.98358345 17.98877907 17.93953705 17.90887833 17.88105583 17.82364655 17.795187 17.79060364 17.73685265 17.71437454 17.66116905 17.63196373 17.5850811 17.55539322 17.51257706 17.44682503 17.41490746 17.36220169 17.30410194 17.27025604 17.21187592 17.17711639 17.12335205 17.09632492 17.02890205 16.97210884 16.90656471 16.85479927 16.77423668 16.73243713 16.70109558 16.59249687 16.57364464 16.51269531 16.42723656 16.38851547 16.29559326 16.23807716 16.17697334 16.13783073 16.05523109 15.99690628 15.8995409 15.83778095 15.75552082 15.72723866 15.64435959 15.56492615 15.50710773 15.42283916 15.38208008 15.30340004 15.22846794 15.14801216 15.10762405 15.02582169 14.96766186 14.86635208 14.81305313 14.75321007 14.74223614 14.65056133 14.59332275 ' ...
        '14.53744888 14.4317522 14.41956139 14.32227898 14.28137112 14.22254848 14.16014576 14.10549927 14.08408737 14.01022816 13.96168518 13.91395378 13.84373283 13.82302475 13.79090118 13.75726795 13.69490623 13.68793869 13.60536098 13.60038567 13.56377792 13.5239439 13.49805641 13.42972946 13.43285179 13.37479782 13.37868404 13.34064007 13.32518578 13.32996082 13.27956295 13.23296738 13.22309971 13.1885891 13.17605782 13.1585865 13.16329575 13.15197659 13.13233376 13.1278677 13.09290218 13.09930229 13.09046268 13.08497334 13.0406332 13.05767155 13.06474781 13.05200577 13.0663929 13.01942158 13.04195499 13.02669334 12.99702549 12.98553085 13.00791073 13.00113487 13.01399422 13.00671864 13.02591705 12.97354698 13.01847649 13.00846958 12.98699856 13.00780773 13.01060772 12.99331951 12.98692513 12.96884537 12.96288395 13.01450729 ' ...
        '12.99894047 13.00491428 12.97175884 12.95886898 12.98561382 12.97130871 13.01230335 13.00234032 12.97178268 13.00150108 13.00440598 12.99960423 12.99744797 12.9999342 13.00616741 12.99346828 12.99506378 12.98954201 13.00840664 12.99864769 13.00045681 12.99944401 13.01021862 13.01669502 13.0008812 12.98071575 12.97678089 12.9858036 12.99724007 13.01062393 12.99477768 12.98835087 13.00135994 13.00019169 13.00766659 12.99901772 12.99324226 12.99022293 12.98285675 12.99661827 12.99398136 13.0070715 12.9982338 12.98208523 13.00850201 13.04194641 13.00216198 13.01345825 13.04865456 13.03005981 13.01774502 13.00186062 13.03674316 13.00474739 13.00986671 13.00636196 13.03901672 13.02484417 13.02684116 13.01349831 13.07452965 13.01825619 13.00036144 13.0741148 13.05289268 13.02797604 13.06849289 13.05016708 13.07685661 13.0453701 ' ...
        '13.05226707 13.03736973 13.05831814 13.08200645 13.05396271 13.03797913 13.0822525 13.06031227 13.08431816 13.09041786 13.08090496 13.08527279 13.07872105 13.08270264 13.10484409 13.11907768 13.09781647 13.09519386 13.11566544 13.12031937 13.11092854 13.1200676 13.12318993 13.13512039 13.13520813 13.16800308 13.12944603 13.16391182 13.14695072 13.13677692 13.15802193 13.18070698 13.19011784 13.15178871 13.19015884 13.18863773 13.24052811 13.18283939 13.19710732 13.22831917 13.20660877 13.23371124 13.2270813 13.22924232 13.23375416 13.25032425 13.22060108 13.23292065 13.23769855 13.24971962 13.23823071 13.23902321 13.27836514 13.24374676 13.27951813 13.28168392 13.27174759 13.24584293 13.26442242 13.29739952 13.27510357 13.29383087 13.27003288 13.29994011 13.31084538 13.30966759 13.29849052 13.28937149 13.34724998 13.34593582 ' ...
        '13.3650322 13.33281231 13.30697727 13.34350109 13.34759426 13.3855238 13.32646275 13.35951042 13.32695198 13.36927128 13.38765144 13.36996555 13.38738632 13.40812874 13.39417553 13.43361855 13.44660664 13.40653896 13.40844154 13.44037247 13.43990707 13.43963432 13.48150253 13.47860146 13.50601578 13.45603466 13.49257851 13.50363922 13.48822403 13.53588867 13.49374676 13.5440979 13.53121281 13.54109383 13.528615 13.52242851 13.58580112 13.55666065 13.59175873 13.59270477 13.61886692 13.56916618 13.58846569 13.62838173 13.64650154 13.59584904 13.65569687 13.61850548 13.63863659 13.67420292 13.67647362 13.68789482 13.68364429 13.64831066 13.67518711 13.73131466 13.72091198 13.69990826 13.70541859 13.73843098 13.73651218 13.72236347 13.77451611 13.77658844 13.77756596 13.7725029 13.79892063 13.79013824 13.80987358 13.80679607 ' ...
        '13.82107162 13.83713341 13.80640221 13.81837273 13.8391819 13.87281609 13.83178234 13.87893105 13.85273457 13.86879253 13.88246155 13.88072205 13.91375256 13.89216518 13.89139748 13.87922192 13.91431236 13.90707684 13.95301342 13.93761826 13.91253948 13.90741062 13.90314865 13.90867043 13.92553043 13.93264389 13.91511154 13.94923019 13.92202663 13.98411274 13.92433167 13.95793247 13.97124958 13.93023109 13.94364834 13.91457748 13.93473721 13.90383434 13.97533417 13.91601086 13.97123051 13.96858692 13.97215271 13.94303608 13.92130566 14.01090908 13.95155334 13.94332981 13.97677994 13.97325993 13.93085003 13.96926975 13.97567272 13.92467213 13.97600174 13.92494583 13.89502144 13.85357857 14.01857185 13.96634007 13.9182415 13.93863869 13.91835499 13.92300987 13.96737957 13.91649055 13.9174509 13.96169376 13.90674877 13.95288849 ' ...
        '13.95740318 13.97931576 14.01136208 13.92056656 13.88016605 13.90282059 13.94715595 13.8781662 13.84727478 13.85903931 13.93322372 13.9245348 13.89576626 13.8769598 13.90741062 13.80379677 13.8571291 13.89029598 13.83159637 13.90310192 13.80167294 13.84281063 13.8220129 13.8240366 13.79049873 13.85493565 13.7525692 13.80390835 13.77000809 13.77846336 13.79178047 13.73749352 13.78951073 13.76045322 13.78523254 13.68488121 13.8040905 13.7148428 13.71181202 13.7294035 13.71484947 13.6662426 13.67336178 13.63088894 13.60579681 13.57677841 13.61905289 13.51987743 13.67996597 13.52067852 13.49776649 13.58724499 13.52807999 13.54852295 13.54198456 13.45843124 13.47368813 13.48087597 13.38793659 13.45653057 ' ...
        ], '%f');
end
function [firstNm, lastNm, reflectance] = est_embeddedGoethite()
    firstNm = 900;
    lastNm = 380.5;
    reflectance = sscanf([ ...
        '33.44715118 33.56050491 33.44511414 33.53852463 33.36420059 33.37311554 33.32720566 33.27433014 33.26696014 33.33283615 33.09607315 33.18089676 33.13835526 33.14818573 33.17089081 33.13302231 33.06507492 33.06186295 33.05204391 32.97099686 32.93283844 32.98342514 32.91477203 32.99016571 32.89442062 32.83113098 32.90306091 32.87519836 32.82696915 32.84622192 32.81851578 32.81444168 32.79742813 32.76506424 32.68041992 32.66659164 32.54153824 32.64406586 32.66553497 32.66838074 32.65758896 32.585289 32.58206558 32.54964447 32.58895874 32.48139572 32.57548141 32.6373024 32.57263947 32.61091995 32.49534225 32.44239044 32.44470215 32.34807205 32.52643204 32.32498169 32.40399933 32.3385582 32.45299911 32.2759285 32.42464447 32.39846039 32.31391144 32.41526413 32.22154236 32.51698685 32.10381699 32.24539948 32.24118805 32.25377655 ' ...
        '32.29495621 32.27968597 32.39220428 32.24180984 32.15516663 32.181427 32.28971863 32.26913834 32.29637527 32.06962967 32.22426605 32.26749039 32.39201736 32.01314926 31.95965576 32.31251907 32.29939651 32.11510468 32.32075119 32.24925232 32.43676376 32.42687988 32.10725403 32.1753006 32.2070961 32.02550507 32.30264664 32.106884 32.42417526 32.07258987 32.35343552 32.1485672 32.1137085 32.12123108 32.33847809 32.28995514 32.39891434 32.31446075 32.53527832 32.19015503 32.27510071 32.43508148 32.36079025 32.25553894 32.37621689 32.47597885 32.34039307 32.29622269 32.63373184 32.69883728 32.31321716 32.37041092 32.57268524 32.41617203 32.38602448 32.74174881 32.60678482 32.40019226 32.81880188 33.04760742 32.68762207 32.39902496 32.69182205 32.71176529 32.54594421 32.93068314 32.78344727 32.89540863 32.92201996 32.95693588 ' ...
        '32.87889099 33.22024536 32.7689743 33.02125549 33.0043602 33.01019669 33.30572128 32.61202621 33.25178528 33.1398201 33.0569458 33.30774689 32.83073425 33.41270065 33.09635925 33.36536789 33.04724884 33.0536499 33.46831512 33.51465988 32.95299149 33.34751511 33.64735413 33.4699707 33.57842255 33.50563812 33.76390457 33.81346893 33.75655746 33.35434723 33.6987381 33.67864227 33.56588364 33.89346313 33.60668564 33.814888 33.95623398 33.53993225 33.57713699 33.91905212 33.81422043 34.41082382 33.92990112 33.71089554 34.09906387 34.02007675 34.18037415 34.13896561 34.12913132 34.375103 34.35033417 34.59583282 34.63275528 34.38608551 34.56641769 34.71982193 34.53949738 34.50151825 34.32422256 34.43092346 34.54506302 34.39691925 34.49863434 34.45469284 34.49124527 34.46823502 34.66683578 34.71503067 34.55900574 34.76973343 ' ...
        '34.75078201 34.74651718 34.95424652 34.96507263 34.97464371 34.88921738 35.00202179 35.00234222 35.13995743 35.23425293 35.27322769 35.21953964 35.30923843 35.28956985 35.40650177 35.40830231 35.33969116 35.49196243 35.46521759 35.56151199 35.73842239 35.58333969 35.67993164 35.79358292 35.82089233 35.89940643 35.93924713 35.91077805 36.00627136 35.99131775 36.08226013 36.16611481 36.06069183 36.1416626 36.07148361 36.29692078 36.28073502 36.409832 36.29615784 36.33250046 36.48195267 36.43070221 36.44760132 36.5104332 36.69821548 36.58682632 36.67204285 36.75450516 36.79772949 36.76395416 36.82603455 36.88603973 36.88003159 37.00567627 36.94011307 36.89939117 37.14610672 37.05316925 37.05874252 37.13318253 37.12504196 37.22414398 37.2161293 37.33493805 37.43207169 37.27296448 37.41246033 37.46240616 37.4908638 37.4200058 ' ...
        '37.491642 37.45426941 37.4672966 37.5393486 37.6249733 37.64754486 37.55662537 37.617939 37.58115005 37.69965363 37.78642654 37.65282059 37.72731018 37.65152359 37.70736313 37.72810364 37.80859756 37.73172379 37.76098633 37.79769897 37.78065872 37.75779724 37.75075912 37.75370789 37.79528809 37.76895905 37.8312149 37.85440445 37.8029747 37.81541443 37.78179169 37.75297165 37.85744476 37.81246185 37.72740173 37.71515656 37.74759293 37.7599411 37.71976471 37.69955444 37.73046875 37.71442032 37.69227982 37.64000702 37.60051727 37.53754425 37.6335144 37.4566803 37.46478271 37.40955734 37.4513855 37.43300629 37.36392593 37.32582474 37.25486374 37.39682388 37.34516144 37.1982193 37.14966202 37.17256165 37.08875656 36.99527359 37.01084137 36.96211243 36.95122528 36.95879745 36.84909439 36.76828003 36.70553589 36.74382019 ' ...
        '36.63269806 36.56705856 36.48304367 36.44829178 36.41433716 36.3236084 36.30490112 36.22774124 36.22374725 36.17602158 36.20704269 36.0015831 35.96814728 35.8891983 35.83679199 35.75489044 35.75627518 35.67980576 35.56519318 35.52471542 35.5502243 35.37441254 35.29348755 35.2754097 35.20675278 35.16283798 35.07912064 34.9668045 34.89263153 34.86039734 34.683918 34.66649246 34.68293381 34.56827927 34.51303101 34.453022 34.34674835 34.28781128 34.22976685 34.15625763 34.10189438 33.93403625 33.93129349 33.9188118 33.80069733 33.71140289 33.68645477 33.55751801 33.51931763 33.35422134 33.36181259 33.26409149 33.22040939 33.14584351 33.06732178 33.04695511 32.96853638 32.89316177 32.80169296 32.74396515 32.66772461 32.59804153 32.51834106 32.42142487 32.37670135 32.3105278 32.24465561 32.13977051 32.05471039 32.03520966 ' ...
        '31.98189735 31.8646946 31.82491875 31.7835083 31.69739532 31.59022713 31.54550743 31.4840889 31.41535568 31.40506363 31.30864143 31.2011776 31.2063942 31.1221962 31.04153252 31.01568604 30.91466522 30.87850189 30.76738739 30.77254295 30.67404556 30.60208511 30.53095627 30.50587463 30.48723412 30.3461132 30.3555603 30.25448608 30.21871758 30.17081642 30.06147766 29.98370171 29.99846649 29.9102211 29.86625671 29.79402924 29.74227715 29.71937943 29.72399902 29.56517029 29.54157639 29.5399971 29.41717529 29.38472939 29.33755302 29.2719574 29.25409698 29.21490669 29.132164 29.10751152 29.03388214 28.99995422 28.9081955 28.89417076 28.84955406 28.81516266 28.75994682 28.66267586 28.65263557 28.65503502 28.59111404 28.53755951 28.45536232 28.41622543 28.37386131 28.35379601 28.32395935 28.25163651 28.15904999 28.19938087 ' ...
        '28.11657143 28.13084984 28.03642082 27.99392128 27.97623062 27.8989563 27.85049629 27.83459663 27.82053947 27.77119827 27.74743462 27.65390587 27.62228012 27.6242981 27.60811234 27.5824337 27.55043793 27.41545486 27.39204407 27.38316345 27.34245682 27.33681107 27.29975891 27.21488571 27.23594284 27.20362854 27.13167381 27.14366531 27.06959915 27.06692123 27.02507019 26.98338699 26.95747948 26.93114853 26.88793182 26.82666397 26.79633141 26.74840736 26.71002769 26.69146729 26.62197685 26.62249184 26.53958893 26.53137398 26.54744911 26.45390701 26.42607689 26.37725258 26.3326416 26.31302834 26.28312492 26.22586441 26.19119263 26.17191887 26.10652733 26.09952736 26.01720428 26.0056076 25.9516201 25.89334869 25.8383007 25.80289268 25.78866196 25.70848083 25.66610527 25.66528702 25.58315468 25.5300293 25.46248817 25.44966316 ' ...
        '25.40130615 25.3218708 25.28434372 25.23803711 25.20180702 25.08997917 25.07115936 24.96676636 24.95520973 24.86048508 24.83038139 24.79850388 24.69911766 24.61948204 24.56377983 24.50234222 24.44768906 24.34682846 24.285326 24.19159508 24.12238693 24.07092667 24.01751518 23.90922546 23.78771019 23.74029732 23.63482475 23.60203171 23.51255989 23.38661003 23.32218742 23.24848747 23.12106514 23.03527069 22.96118355 22.82200623 22.7252388 22.60639 22.55733681 22.44897079 22.35136223 22.18271637 22.11306763 22.03662491 21.88353729 21.75776863 21.69202805 21.57869148 21.43817902 21.29207611 21.20386124 21.11664009 20.95786285 20.83275986 20.73735809 20.60787964 20.49059105 20.38822937 20.25231552 20.1144886 20.00199127 19.85812569 19.71683884 19.65197754 19.50912666 19.37738419 19.2568512 19.12177277 19.0064373 18.86185074 ' ...
        '18.74334717 18.62044716 18.52602386 18.3927269 18.29047585 18.17298889 18.02893639 17.94498825 17.7562542 17.68684959 17.54511261 17.44884491 17.35896301 17.24150085 17.14905167 17.06197739 16.94823265 16.82072639 16.75201035 16.64628029 16.53406525 16.45563698 16.37035751 16.28149223 16.16342163 16.08963966 16.00152779 15.96609974 15.86570263 15.77000809 15.70552921 15.57951832 15.53072739 15.43364334 15.35439301 15.32667446 15.26415062 15.21718216 15.09265327 15.081213 14.97929955 14.94620323 14.89672375 14.8195343 14.77400494 14.7318821 14.67584705 14.62812996 14.61021709 14.54750633 14.49795628 14.465868 14.39676476 14.37802887 14.3601656 14.31337166 14.27751064 14.2237606 14.18156147 14.16790771 14.14639473 14.11631966 14.08330059 14.02880096 14.04255676 14.01089001 13.98622799 13.96185303 13.90701675 13.90914726 ' ...
        '13.90140343 13.86547565 13.84774113 13.81297874 13.80091476 13.78847504 13.77501488 13.79388428 13.75588608 13.773139 13.74928761 13.68470955 13.68190956 13.67823792 13.67282009 13.64923573 13.64067936 13.63074017 13.60923195 13.60552502 13.5952177 13.56557655 13.54865551 13.55697632 13.56201649 13.54445648 13.52228069 13.56492329 13.54607487 13.48487759 13.53536415 13.51200294 13.51752472 13.46821213 13.47275925 13.50393772 13.48244381 13.44693279 13.49009609 13.45914173 13.44378281 13.43671417 13.44280529 13.45736217 13.4388876 13.43198872 13.41958332 13.42724419 13.41327572 13.40841389 13.41508007 13.4022522 13.42817116 13.41397476 13.39789295 13.40156746 13.43123627 13.42977619 13.41975307 13.40336323 13.39265442 13.40604877 13.37877178 13.3999033 13.39159012 13.4071722 13.38290977 13.36860466 13.39387321 13.36276054 ' ...
        '13.40059948 13.39991379 13.39428902 13.36426163 13.35899258 13.40435028 13.38825703 13.37662506 13.38548946 13.41867733 13.38783073 13.39458561 13.37381458 13.36727905 13.38118649 13.37806892 13.38680077 13.3836937 13.37390232 13.3734045 13.38363266 13.4052515 13.39461517 13.38701725 13.34708309 13.39659214 13.38116264 13.40821075 13.37529278 13.38882256 13.40474224 13.36933041 13.39607239 13.38198471 13.37713146 13.3929491 13.38525105 13.40517712 13.3713913 13.39336777 13.38093567 13.36934853 13.39604282 13.36207867 13.36433697 13.38040829 13.38831139 13.40420532 13.37739182 13.40275288 13.39608002 13.37588596 13.39842701 13.35325813 13.39387703 13.4049778 13.39107132 13.38115311 13.39582825 13.39934444 13.38926125 13.39706326 13.39415359 13.40049076 13.40833282 13.41228199 13.37413502 13.38300228 13.38962746 13.43833923 ' ...
        '13.40780258 13.39020252 13.42101955 13.40613937 13.40527248 13.38983345 13.42113876 13.43227005 13.4545269 13.41503906 13.37807751 13.425457 13.42937088 13.42090225 13.41977978 13.42910099 13.41581059 13.39806652 13.4323616 13.46977806 13.41158867 13.42649746 13.41649246 13.44741249 13.45604801 13.40065193 13.47884083 13.4481802 13.47025299 13.44970894 13.45643425 13.4202261 13.43663597 13.4729147 13.43660355 13.48390007 13.48502064 13.45502758 13.52436733 13.47007751 13.47494698 13.4354744 13.48535538 13.46945477 13.48807049 13.49971771 13.47824478 13.51227474 13.47615528 13.46321106 13.46516895 13.51453495 13.47728634 13.46618938 13.5003891 13.5375185 13.48237133 13.49579716 13.47737598 13.51050568 13.5291214 13.5313797 13.491395 13.52676582 13.51241302 13.53661156 13.5292511 13.52601051 13.56466103 13.52227211 ' ...
        '13.55094719 13.5331974 13.52104664 13.51225948 13.52771378 13.54528236 13.52678871 13.53030682 13.5591135 13.48749828 13.5331707 13.53255177 13.52937412 13.55445862 13.55293369 13.52100372 13.57845211 13.52230263 13.53839684 13.58203316 13.51591778 13.58226395 13.52613449 13.52883434 13.52549458 13.56266594 13.51479626 13.51407909 13.49972916 13.52797031 13.53236771 13.5102005 13.49579811 13.55251694 13.52701187 13.54232693 13.53597641 13.53667545 13.56725883 13.53132534 13.5277195 13.56391048 13.50807667 13.51299 13.56211758 13.57669353 13.54865456 13.57487583 13.55722809 13.56683254 13.54747581 13.56933975 13.53097248 13.54019642 13.52317333 13.53801155 13.54298878 13.50076962 13.53197289 13.59426212 13.54679585 13.52980423 13.54726124 13.50910378 13.55189705 13.50031376 13.54917908 13.5266695 13.48277187 13.54456425 ' ...
        '13.50963688 13.56585884 13.5819273 13.49145889 13.61258507 13.59029388 13.52049446 13.48478222 13.50640678 13.45522404 13.51347446 13.55790901 13.46714497 13.54001045 13.48157406 13.47407818 13.48382664 13.50510311 13.44859791 13.47143936 13.43012142 13.43206787 13.47747135 13.48765373 13.48711586 13.52088642 13.46707153 13.46824932 13.49612427 13.40417671 13.42309093 13.40462399 13.35479641 13.46074772 13.45562363 13.42062664 13.42986679 13.37447643 13.44688988 13.29690075 13.38318253 13.38456249 13.29485798 13.36424637 13.34213638 13.33659744 13.2572937 13.42337608 13.31858349 13.22548962 13.34744835 13.32292747 13.30422878 13.26627159 13.36426449 13.21188831 13.31439304 13.30661297 13.31112671 13.20890236 ' ...
        ], '%f');
end
function [firstNm, lastNm, reflectance] = est_embeddedGypsum()
    firstNm = 2600;
    lastNm = 350.5;
    reflectance = sscanf([ ...
        '37.34040451 36.19244385 37.57865906 37.38893127 36.24979401 37.15520859 36.87025452 36.09050369 37.20343018 36.82410431 36.69591522 36.47359848 36.13031387 36.79000854 36.6584053 37.77718735 37.25017166 37.20018387 37.37411499 36.98946762 36.51991272 38.19107819 36.62148285 36.40185165 35.80443192 36.12783051 37.12185669 36.11205673 36.6315155 36.97962189 36.88860321 35.91299438 37.13326645 36.88478088 37.94321823 37.6916008 36.09951782 37.11938858 36.16122818 36.5579567 37.4942627 36.65950775 36.32145691 36.11922073 36.25112915 36.81033707 36.46963501 36.92336273 36.44678116 37.16807938 36.64706802 36.27690887 37.33574295 36.84975052 37.04330444 36.30815887 36.46903229 36.65691757 36.18468094 37.00391769 37.29996872 36.7774353 36.65182114 37.34053421 36.43939972 37.73775864 36.89769745 36.49546814 37.31479263 37.38272476 ' ...
        '37.00610733 36.66050339 36.19902802 36.97119522 37.57616425 37.32829666 36.55665207 36.72153854 37.36798096 37.34170914 37.09309387 37.10586548 37.12786484 37.61499405 37.71423721 37.1100769 37.13119888 37.23870087 37.77486801 37.56300354 37.09179306 37.55839539 37.48054123 37.07369995 37.40553665 37.129776 37.24143219 37.72851181 37.48412704 37.30170059 37.57796097 37.64351654 37.44062042 37.45546341 37.57757568 37.64139175 37.20821381 37.49916077 37.50945663 37.41599655 37.85199356 37.29041672 37.34728622 37.51437378 37.65643692 37.68195343 37.40836716 37.53564835 37.40725327 37.65991211 37.55094528 37.69374466 37.55315399 37.80621719 37.69418716 37.80358505 37.68043518 37.53977966 37.70949173 37.30846786 37.42416 37.81093597 37.66526794 37.42447662 37.47675705 37.68967438 37.62881088 37.22544098 37.92547226 37.62345123 ' ...
        '37.76047134 37.09500122 37.44919586 37.44695282 37.39943695 37.28898239 37.20199585 37.2393074 37.04751587 37.54177094 37.06818008 37.24757385 37.15452576 37.2792244 37.07636261 37.07505035 37.14344788 37.13398361 37.29304123 36.86791229 36.99541473 36.76248932 37.01174927 36.94646835 36.85063934 36.87897491 36.85836029 36.85592651 36.88628769 36.590271 36.66459656 36.57690811 36.66608429 36.50539398 36.69394684 36.55177307 36.54187393 36.59501648 36.41976929 36.47112274 36.61652374 36.40372086 36.10273743 36.34434509 36.17293167 36.40340042 36.33979034 36.15276337 36.26268387 35.81636429 36.21751404 36.09540939 36.01807022 36.02655411 35.99445724 35.99560547 35.81558228 35.85167694 35.76987839 35.80203629 35.82565308 35.81602097 35.85559464 35.77723694 35.64655685 35.78792953 35.47117996 35.62720108 35.65748596 35.5473938 ' ...
        '35.50246048 35.53578186 35.55506134 35.69719315 35.55437088 35.44137192 35.49646759 35.52171707 35.33751678 35.56738663 35.5917244 35.42822266 35.54460907 35.39059067 35.37903976 35.50468063 35.49346924 35.41629791 35.35144424 35.46538925 35.32692337 35.40031815 35.47209167 35.33610916 35.41523361 35.4673233 35.48008347 35.51214218 35.49151993 35.5335083 35.41103745 35.59383011 35.6300087 35.39805222 35.53674316 35.60051727 35.78062057 35.71313477 35.65864563 35.72329712 35.6745491 35.64316559 35.78556061 35.85734177 35.83430862 35.81642532 35.94942856 36.05657578 36.08459091 36.01467896 36.22235107 36.00720978 36.10276794 36.17469788 36.32049942 36.43605423 36.3001976 36.44569016 36.47026825 36.45487595 36.58872604 36.48707962 36.75328064 36.66164398 36.70884705 36.84896088 36.83771896 36.9220047 36.86841202 37.02977753 ' ...
        '36.98800278 37.04589844 37.09080887 37.12000275 37.16623306 37.26071548 37.16957092 37.3111763 37.27389526 37.30159378 37.38801956 37.45653915 37.54482651 37.54800415 37.51011658 37.56997299 37.54530716 37.44149017 37.70828247 37.62313843 37.61968231 37.75599289 37.73614502 37.66448212 37.72165298 37.88035583 37.91416168 37.70903397 37.87270355 37.82379532 37.81425858 37.82090378 38.03299713 37.96805191 38.08641052 38.05437088 38.16696548 38.01405716 38.14200211 38.00650406 38.11153793 38.134758 38.17847824 38.22203445 38.27251434 38.28765106 38.28371811 38.48183441 38.35572052 38.34607697 38.39437866 38.539505 38.51403427 38.45400238 38.52947235 38.61217117 38.64564896 38.58159637 38.77273941 38.76438522 38.80945206 38.73429871 38.84985733 38.89680862 38.93877792 39.08003235 39.23317719 39.03066254 39.18095016 39.17415237 ' ...
        '39.26480865 39.47965622 39.394207 39.46621704 39.49619293 39.56131744 39.66350937 39.86032104 39.73684311 39.9355545 40.02462769 39.99451828 39.97667694 40.24807358 40.31510162 40.34301376 40.43624878 40.61668396 40.50686264 40.73243713 40.82107162 40.95700836 41.0564003 41.18781281 41.30382919 41.39466858 41.48606873 41.56338501 41.77520752 41.86407089 42.03224182 42.09117508 42.23663712 42.34481049 42.48209763 42.65333176 42.80093384 42.90098572 43.05854034 43.29092026 43.39254761 43.53239059 43.77719879 43.89448166 44.14489365 44.28039551 44.42786789 44.65663528 44.75927734 44.97924423 45.06997299 45.26609039 45.3751564 45.69215393 45.87275696 45.94368744 46.24430084 46.37633896 46.55438232 46.80797577 46.93446732 47.16262817 47.31703568 47.49126816 47.58623123 47.84288025 48.03375626 48.12071228 48.39977264 48.56482697 ' ...
        '48.78018951 48.96508026 49.11403656 49.34834671 49.43846893 49.7473526 49.86730957 50.09090805 50.26398849 50.42815399 50.70637894 50.80845261 50.95519257 51.13967514 51.25724792 51.48155212 51.65651321 51.876091 51.95131302 52.18670273 52.3113327 52.39910889 52.59070969 52.68381119 52.93896103 53.02974701 53.2693634 53.34858704 53.61713791 53.75125504 53.86940384 53.9088974 54.1008606 54.27973938 54.44001389 54.55441284 54.69877243 54.77197647 54.8714447 55.06188202 55.17850494 55.33755875 55.48323822 55.5725975 55.70526123 55.82374954 55.98480225 56.10767746 56.20892715 56.33773804 56.44895935 56.52445602 56.65179062 56.76227188 56.80771637 56.94759369 57.07772446 57.15913773 57.25486374 57.44754791 57.50910568 57.58264542 57.69539642 57.77406693 57.8408432 57.95619583 58.08135986 58.19113922 58.30741501 58.45434189 ' ...
        '58.38674927 58.59041214 58.58525467 58.73518753 58.76348495 58.81707001 58.88331985 59.03627396 59.1523056 59.14891815 59.25166702 59.36946869 59.44253922 59.51612473 59.53593445 59.6572113 59.69950485 59.7520752 59.86207199 59.90212631 59.90790176 60.01568985 60.09407043 60.1421814 60.22801971 60.20364761 60.31315231 60.38793945 60.4351387 60.50146866 60.56622696 60.61724854 60.65440369 60.72269821 60.74160385 60.7715683 60.84322357 60.9176445 60.97171402 61.05215454 60.98482513 61.09514999 61.08229065 61.18529892 61.22497177 61.24733734 61.1825943 61.2908783 61.3652153 61.36204147 61.39551544 61.42757416 61.47481155 61.53679657 61.49709702 61.57171249 61.5281601 61.63539124 61.58221436 61.6257782 61.63809967 61.71406937 61.67685318 61.68419647 61.75819778 61.77415848 61.76587296 61.82239151 61.83086777 61.82017517 ' ...
        '61.83553314 61.87750626 61.86668777 61.89097595 61.9565773 61.89367294 61.90776825 61.94282913 61.91977692 61.94599152 61.97519302 61.92206192 61.96361923 61.98010254 61.90659332 61.95165634 62.01946259 61.9283371 61.93303299 61.92651367 62.03536224 61.96056747 61.91682816 61.97524261 61.99459839 61.91561127 61.92586517 61.91573715 61.94114685 61.96082306 61.94341278 61.95789719 61.88809204 61.97006607 61.85755157 61.89294434 61.80712128 61.79840088 61.83104706 61.83660507 61.81658936 61.75709534 61.71249771 61.76491547 61.72906876 61.69628906 61.74040985 61.67580414 61.71557236 61.60766602 61.55542755 61.5794487 61.50884628 61.48628998 61.46460724 61.41070557 61.50088501 61.40074158 61.33856964 61.30396652 61.29021072 61.25889969 61.17232895 61.18742752 61.07435989 61.11477661 60.93880463 60.9493866 60.87559891 60.86646271 ' ...
        '60.81013489 60.7234726 60.67753983 60.61806107 60.6496582 60.56653976 60.50301743 60.37006378 60.37392426 60.22703171 60.25209427 60.22132111 60.09402847 60.12247086 59.98860168 59.95017242 59.91326141 59.82149887 59.67851257 59.68153381 59.65846634 59.61066055 59.4581604 59.51802063 59.50576019 59.45953751 59.3319664 59.31367874 59.28147888 59.22483826 59.22357559 59.2361145 59.12952423 59.19264984 59.18126678 59.09825516 59.10206985 59.09722519 59.11208344 59.00244904 59.15710831 59.1529541 59.1062851 59.11767578 59.16500092 59.06783295 59.10855103 59.13380432 59.14813995 59.23384476 59.24951935 59.13098526 59.27109146 59.21268463 59.28189087 59.29180527 59.35158157 59.4000473 59.46435165 59.39631653 59.49163437 59.52513123 59.53427124 59.5006752 59.48060608 59.49015808 59.58369446 59.61804962 59.60441971 59.60216522 ' ...
        '59.59372711 59.59850693 59.55384445 59.59431458 59.60834122 59.58604813 59.53821564 59.60410309 59.60609818 59.55459976 59.53096008 59.53450012 59.5221405 59.47763824 59.54500961 59.51793671 59.5146904 59.38835907 59.3718605 59.3868866 59.36587524 59.24296951 59.26463699 59.20582581 59.12687302 59.09703445 59.05107117 59.04818726 59.05076218 58.89897156 58.80086517 58.74965286 58.76476669 58.64782333 58.5954895 58.52659988 58.44795609 58.42052841 58.31930542 58.22513199 58.17856598 58.06434631 58.06237411 57.99573517 57.97919464 57.81968689 57.81792831 57.59585571 57.64155579 57.59623718 57.50186539 57.39374924 57.46092987 57.33716583 57.35552979 57.25638199 57.2586174 57.16904831 57.0524025 57.01904297 57.0436554 57.08263397 57.00976944 56.9663887 56.9314003 56.88822174 56.91096115 56.84672165 56.88206482 56.90800095 ' ...
        '56.88349152 56.85650253 56.87448502 56.95309067 56.92975998 56.93531036 56.95157623 57.02162933 57.01232529 57.06983185 57.02990723 57.09597397 57.14582062 57.16576385 57.29177475 57.26875687 57.37078857 57.35200119 57.41956329 57.41998672 57.48223495 57.57659149 57.60368729 57.69152069 57.76343918 57.76210022 57.83275223 57.90005875 57.86751938 57.90192413 57.95479965 58.03726196 58.12209702 58.10525894 58.20517731 58.17274475 58.18537521 58.26909637 58.35445023 58.35321426 58.46809769 58.43096542 58.41978836 58.57492065 58.57938004 58.61221695 58.6242485 58.64993286 58.72501755 58.70975876 58.73890686 58.69037628 58.76175308 58.84436417 58.82195663 58.9294548 58.92373276 58.9178009 58.95454407 58.97613907 58.98812866 59.07736588 59.09605026 59.03435516 59.14217758 59.13921738 59.17211151 59.19289017 59.20062256 59.2834816 ' ...
        '59.25056839 59.33508301 59.3647728 59.43674469 59.39676285 59.4588356 59.49499512 59.54440689 59.52898407 59.53084183 59.60966492 59.6825943 59.66610336 59.66217422 59.76078415 59.80003357 59.88864899 59.87264633 60.04526138 59.99838257 60.09228134 60.10105515 60.17466354 60.21266174 60.27923203 60.33526611 60.39416885 60.47673035 60.50584412 60.59239578 60.61373901 60.65344238 60.78141785 60.79201508 60.91465378 60.91623306 61.01900864 61.10144424 61.15012741 61.21709442 61.25325012 61.3312645 61.36907959 61.4803009 61.56310272 61.60354614 61.67804718 61.68203354 61.74796677 61.85425949 61.87198257 62.00797653 62.00826645 62.11116409 62.15855408 62.23683167 62.29898453 62.3680954 62.4157486 62.50141907 62.53356171 62.56145096 62.70418167 62.75508499 62.83534241 62.84775543 62.92108917 62.99267578 62.97727966 63.03532791 ' ...
        '63.17196655 63.15377808 63.19268417 63.27974319 63.30346298 63.36503601 63.45248795 63.46602631 63.50815201 63.56222153 63.64929581 63.67393875 63.78880692 63.74158096 63.86200714 63.91772461 64.00892639 63.996418 64.07250977 64.0851059 64.09398651 64.21507263 64.24350739 64.31287384 64.2773819 64.368927 64.46186066 64.48579407 64.49616241 64.56597137 64.60112762 64.68572998 64.76561737 64.74716949 64.79640198 64.87348938 64.93206787 64.97159576 65.00733948 65.08727264 65.10216522 65.2066803 65.25804901 65.31576538 65.33024597 65.34223938 65.4134903 65.47370911 65.50935364 65.58353424 65.63776398 65.69943237 65.73587036 65.80531311 65.82328033 65.85771942 65.8997879 66.0359726 66.06594086 66.09721375 66.18480682 66.21633911 66.274086 66.33732605 66.37324524 66.40616608 66.46237946 66.54390717 66.65871429 66.70610046 ' ...
        '66.69063568 66.76564026 66.89385986 66.91030884 66.97026825 66.9726944 67.04727173 67.12390137 67.11920166 67.2113266 67.30854797 67.3841629 67.32453156 67.45990753 67.5039978 67.54716492 67.58693695 67.6987381 67.70914459 67.69319916 67.78047943 67.87129974 67.88906097 68.00415039 68.06868744 68.0389328 68.15857697 68.12042236 68.18045807 68.26908875 68.31907654 68.34885406 68.35746765 68.41343689 68.41532135 68.45632935 68.57688141 68.59458923 68.59325409 68.65731049 68.69471741 68.73271179 68.69761658 68.78134155 68.81889343 68.8396225 68.86728668 68.89292145 68.89797974 68.92093658 68.94077301 68.98814392 69.01873016 68.99182892 69.0223999 69.10241699 69.11390686 69.07719421 69.13273621 69.12287903 69.11761475 69.13755798 69.16870117 69.19018555 69.21832275 69.26057434 69.18100739 69.20557404 69.25955963 69.30904388 ' ...
        '69.26839447 69.25109863 69.28650665 69.26535034 69.24636078 69.26996613 69.25997925 69.30878448 69.30032349 69.25331116 69.28255463 69.24054718 69.28704834 69.25782013 69.30365753 69.26142883 69.32994843 69.29573059 69.30034637 69.29502869 69.3127594 69.30130005 69.28827667 69.3397522 69.33482361 69.30885315 69.29386902 69.31460571 69.2980957 69.32203674 69.32158661 69.27949524 69.28500366 69.20896912 69.28282928 69.28279114 69.2593689 69.25206757 69.26030731 69.23434448 69.18560791 69.20877075 69.25418091 69.15086365 69.19178772 69.13522339 69.12549591 69.1149292 69.08875275 69.0249939 69.05406952 69.01271057 68.974823 68.93719482 68.94494629 68.88230133 68.87750244 68.81576538 68.76811218 68.77037048 68.71475983 68.66738892 68.57785797 68.56079865 68.51035309 68.42224884 68.42282867 68.31380463 68.2977829 68.2004776 ' ...
        '68.14846039 68.12691498 68.00271606 67.95733643 67.92658234 67.85114288 67.77898407 67.68127441 67.61721039 67.57222748 67.47870636 67.34197998 67.25637817 67.21960449 67.14480591 67.06395721 66.93782806 66.85332489 66.80046082 66.69048309 66.55261993 66.49504852 66.31547546 66.2376709 66.17077637 66.04152679 65.95162964 65.79908752 65.66047668 65.58667755 65.42188263 65.29476929 65.16378784 65.03388977 64.88183594 64.74404144 64.59005737 64.45494843 64.33234406 64.15210724 63.97346878 63.83969879 63.64364624 63.53110123 63.32740784 63.08070374 62.96902466 62.74845123 62.5642128 62.3439064 62.11901474 61.90897369 61.6995163 61.46599579 61.24868393 61.0487442 60.78715515 60.53778458 60.24760056 59.98851013 59.72444534 59.46722031 59.14248276 58.91053009 58.60017395 58.32156372 58.03046799 57.66915131 57.44156265 57.05780411 ' ...
        '56.76553345 56.46935654 56.14903641 55.81761551 55.46186066 55.1476059 54.76219559 54.44934845 54.10568237 53.77218246 53.43051147 53.12359238 52.76714706 52.39204788 52.15371323 51.72426224 51.42452621 51.08685303 50.73297501 50.41353226 50.1014061 49.76703262 49.42764664 49.11644745 48.83090973 48.51491165 48.23667526 47.91521454 47.66217804 47.36553574 47.08330154 46.81407928 46.59801102 46.33066559 46.07509232 45.79109192 45.62734222 45.32685852 45.11309433 44.95558929 44.75177383 44.51207352 44.31613159 44.14375305 43.93998337 43.76583099 43.66058731 43.46023941 43.306633 43.15358734 42.98667145 42.87178421 42.7599144 42.61244965 42.44826889 42.36381531 42.25612259 42.11655045 41.99394989 41.9232254 41.76140594 41.66155624 41.56520462 41.42858505 41.34484482 41.23297119 41.1032486 41.03342438 40.91169357 40.81926727 ' ...
        '40.68066788 40.586689 40.47071838 40.36923981 40.23340225 40.13370132 39.97681427 39.88082886 39.69964218 39.56016541 39.47739792 39.3072319 39.15169525 39.00192642 38.84829712 38.72674561 38.57841492 38.41356277 38.26341248 38.09443665 37.93360138 37.75901031 37.60919952 37.41717529 37.28490067 37.10352325 36.93421173 36.75484848 36.59473801 36.39347076 36.26195908 36.11302185 35.94788361 35.80185318 35.65161514 35.49882507 35.32700348 35.22928619 35.09221268 35.00069809 34.87704468 34.73053741 34.66319275 34.59015274 34.48720932 34.38225174 34.31642151 34.28565979 34.23744965 34.15460968 34.15195465 34.15855026 34.12509918 34.12462997 34.12599182 34.18480682 34.20308685 34.21429443 34.30088043 34.36593628 34.43890381 34.51757431 34.59138107 34.68673706 34.83276749 34.95925522 35.08423233 35.27689743 35.45478439 35.5764389 ' ...
        '35.74608994 35.98175812 36.16410446 36.38991165 36.61505127 36.8216629 37.02030945 37.30357361 37.53838348 37.78286743 38.03433228 38.30963135 38.5366478 38.86477661 39.1498909 39.44674683 39.68743515 40.03422546 40.3455162 40.60653687 40.93742752 41.27334976 41.60195541 41.90269852 42.19690704 42.49250793 42.81594467 43.15477753 43.51225281 43.80151367 44.16553497 44.48761368 44.79600906 45.11185455 45.43844986 45.77610016 46.10332108 46.41485977 46.72327805 47.10544205 47.41970444 47.75039291 48.03870773 48.37687683 48.72379303 49.04633713 49.38453293 49.67930984 50.03292465 50.3249588 50.63803864 51.01155472 51.30469894 51.62522125 51.93190765 52.29335022 52.59770584 52.88235092 53.26351929 53.56735992 53.86654663 54.16399765 54.45526123 54.80546951 55.13516617 55.42530823 55.75416565 56.04272461 56.33426285 56.64159775 ' ...
        '56.95636749 57.24636841 57.55631256 57.83926392 58.17736435 58.50741196 58.76182938 59.06958771 59.3909874 59.69430923 59.96199799 60.229599 60.51818848 60.79027557 61.05731201 61.35225296 61.66101074 61.89348221 62.16333389 62.44535446 62.73166656 62.96125793 63.22296143 63.48255157 63.7225647 63.99998474 64.2726593 64.54003143 64.79342651 65.04452515 65.29942322 65.55357361 65.79972839 66.08841705 66.3539505 66.61080933 66.90116882 67.1139679 67.46836853 67.710289 67.97325134 68.26822662 68.5045166 68.78863525 69.06037903 69.32514954 69.61469269 69.90402985 70.14785767 70.43070221 70.70323181 70.98908234 71.24698639 71.53707123 71.76291656 72.04927063 72.27642822 72.56242371 72.80686188 73.07294464 73.34170532 73.56306458 73.81242371 74.09450531 74.30439758 74.5554657 74.76725769 74.98690033 75.19761658 75.42562866 ' ...
        '75.61203003 75.83420563 76.05186462 76.18025208 76.41540527 76.58432007 76.75824738 76.93286896 77.09254456 77.19135284 77.37010956 77.56142426 77.67900848 77.85664368 77.94869232 78.11038208 78.205513 78.34786987 78.49564362 78.575737 78.66191101 78.7956543 78.92829132 78.9779129 79.08901978 79.19062042 79.30805969 79.38264465 79.46298981 79.59470367 79.65909576 79.7381134 79.81380463 79.90950775 79.94854736 80.05819702 80.11340332 80.18167877 80.21876526 80.29814148 80.36019135 80.41969299 80.45396423 80.52310181 80.59823608 80.6374054 80.67077637 80.72224426 80.75789642 80.73999786 80.83020782 80.86159515 80.85042572 80.91712189 80.92871094 80.95470428 80.98655701 80.99784851 81.04058075 81.05156708 81.0538559 81.05728912 81.07979584 81.10263062 81.07678223 81.08700562 81.09462738 81.09933472 81.10334015 81.14920044 ' ...
        '81.10205841 81.11117554 81.14470673 81.09859467 81.09868622 81.09140015 81.07712555 81.05725861 81.08276367 81.09356689 81.05509949 81.02746582 81.01376343 80.99195099 80.96906281 80.97825623 80.95567322 80.94300842 80.89203644 80.90258789 80.87012482 80.86849213 80.81008148 80.82975006 80.77116394 80.76908875 80.69364166 80.67178345 80.6700592 80.62442017 80.6053009 80.55179596 80.51977539 80.50188446 80.44904327 80.39108276 80.36148071 80.32939148 80.29986572 80.23834229 80.19726563 80.15781403 80.11473846 80.05670929 80.01937866 79.94665527 79.90589905 79.84483337 79.79328918 79.76296234 79.66792297 79.63716125 79.55374908 79.51908875 79.4497757 79.37522888 79.29230499 79.25788879 79.18362427 79.1033783 79.03244781 78.97650909 78.87902832 78.80019379 78.75312805 78.67683411 78.59166718 78.51678467 78.41413116 78.34102631 ' ...
        '78.24623871 78.19039154 78.11193085 78.00212097 77.92952728 77.87545013 77.77870941 77.69013977 77.62464905 77.52403259 77.4487915 77.37823486 77.26483917 77.17861176 77.11670685 77.02823639 76.95336914 76.88168335 76.79188538 76.70152283 76.65341187 76.54252625 76.50257111 76.4310379 76.34261322 76.30412292 76.20118713 76.14957428 76.06917572 76.02319336 75.94019318 75.88803101 75.81978607 75.75798798 75.72681427 75.65483093 75.58842468 75.53801727 75.48823547 75.44325256 75.39943695 75.31790924 75.30088806 75.21854401 75.17967987 75.16165161 75.09620667 75.0572052 75.00340271 74.94165802 74.90736389 74.87146759 74.81850433 74.77009583 74.71619415 74.6987915 74.64096832 74.57971191 74.54193878 74.50650024 74.45655823 74.41466522 74.36597443 74.31917572 74.27729034 74.22057343 74.18616486 74.13283539 74.07892609 74.05461884 ' ...
        '74.00015259 73.97303009 73.91583252 73.90039063 73.84250641 73.8097229 73.78418732 73.72776031 73.7009964 73.68814087 73.64823914 73.62110901 73.60645294 73.60137939 73.55432129 73.55783081 73.55145264 73.55003357 73.56409454 73.52305603 73.57120514 73.5785141 73.57844543 73.60050964 73.62369537 73.65336609 73.69898987 73.73176575 73.78136444 73.8207016 73.88887024 73.93128967 73.99695587 74.04715729 74.13426971 74.21564484 74.29915619 74.37310028 74.45569611 74.55775452 74.64472198 74.74362183 74.87607574 74.97047424 75.10183716 75.19284821 75.34342957 75.44444275 75.58027649 75.69908142 75.84183502 75.98603821 76.1233139 76.26059723 76.41234589 76.5485611 76.70837402 76.86901093 77.0185318 77.1571579 77.32798004 77.47549438 77.63052368 77.8134613 77.97444153 78.13815308 78.29253387 78.46790314 78.63904572 78.80072784 ' ...
        '78.96982574 79.14196014 79.30601501 79.457901 79.64093781 79.79166412 79.96199799 80.14619446 80.29289246 80.47879028 80.63806152 80.80139923 80.95906067 81.11755371 81.30541229 81.44979858 81.5955658 81.78022003 81.92543793 82.10437012 82.2387085 82.39732361 82.55601501 82.71511078 82.86117554 82.99217987 83.16068268 83.30947876 83.46632385 83.59895325 83.7195282 83.88629913 84.01448822 84.15811157 84.28562164 84.41690063 84.55708313 84.68321228 84.80286407 84.93496704 85.04466248 85.18159485 85.30815125 85.40562439 85.50299072 85.6395874 85.75895691 85.8531723 85.96914673 86.04928589 86.16513824 86.26248932 86.36134338 86.44625854 86.54418182 86.64737701 86.73132324 86.79891205 86.89878845 86.99146271 87.04794312 87.11943817 87.21387482 87.28575897 87.35012054 87.40988922 87.50469971 87.56912994 87.59828186 87.66680908 ' ...
        '87.7378006 87.78646851 87.84282684 87.89050293 87.94277954 87.98294067 88.04484558 88.0925827 88.13871765 88.18282318 88.19306183 88.24507904 88.27549744 88.31549072 88.35761261 88.39733887 88.41023254 88.45001984 88.46200562 88.4977951 88.51200867 88.54120636 88.58750916 88.59025574 88.61541748 88.612854 88.6398468 88.65518188 88.68364716 88.67492676 88.67025757 88.72188568 88.70809174 88.73719788 88.72161865 88.74853516 88.73918915 88.74267578 88.74671173 88.75540161 88.75085449 88.74491882 88.75409698 88.75732422 88.74871826 88.74215698 88.74205017 88.73345184 88.71891785 88.71535492 88.71230316 88.70101929 88.69573212 88.67466736 88.6542511 88.66370392 88.64805603 88.62483215 88.58804321 88.59294128 88.55722809 88.56180573 88.54415131 88.52136993 88.49641418 88.49638367 88.45343781 88.42529297 88.43049622 88.40690613 ' ...
        '88.37168121 88.35183716 88.3171463 88.30158234 88.27974701 88.24748993 88.20838928 88.19036865 88.16173553 88.1184845 88.10919189 88.07676697 88.04219055 88.00669098 87.99144745 87.95477295 87.91703796 87.87444305 87.85433197 87.81542969 87.77971649 87.75513458 87.69358826 87.66390991 87.64521027 87.58810425 87.55418396 87.52095032 87.48815155 87.44036865 87.39282227 87.37117767 87.30857849 87.27620697 87.23547363 87.19095612 87.15936279 87.1088028 87.0818634 87.04704285 86.9914093 86.9591217 86.90019989 86.86717987 86.81443024 86.77763367 86.73786163 86.68508911 86.64138031 86.60494995 86.54853821 86.51515198 86.48596954 86.42075348 86.39373779 86.33374023 86.29333496 86.24687195 86.1882782 86.14941406 86.09566498 86.0637207 86.00003052 85.97171783 85.90827942 85.8613739 85.81179047 85.77583313 85.72331238 85.66190338 ' ...
        '85.61626434 85.56549072 85.52824402 85.47131348 85.41374207 85.3768158 85.31794739 85.26011658 85.22285461 85.16640472 85.10688019 85.06031799 84.99487305 84.93971252 84.87362671 84.83050537 84.75724792 84.71840668 84.64905548 84.59918213 84.53514099 84.4864502 84.41532898 84.37497711 84.32421112 84.25283813 84.19998169 84.13071442 84.05274963 84.00398254 83.95217896 83.88175201 83.82320404 83.75830841 83.69851685 83.63036346 83.58104706 83.50630188 83.44316101 83.39167023 83.31626892 83.26473236 83.19332886 83.12164307 83.07501221 82.99511719 82.94320679 82.87528992 82.81800842 82.74839783 82.69245911 82.62562561 82.56300354 82.50447083 82.44033813 82.37805939 82.32913971 82.24863434 82.19099426 82.14081573 82.07481384 82.0100708 81.93539429 81.87971497 81.83039856 81.77210999 81.69902802 81.63851166 81.56615448 81.50429535 ' ...
        '81.44248962 81.38777924 81.32850647 81.25141144 81.20497894 81.12998962 81.06316376 81.01320648 80.94000244 80.8826828 80.79736328 80.74808502 80.6721344 80.59615326 80.55486298 80.46743774 80.39357758 80.325737 80.26399231 80.19993591 80.1320343 80.04789734 79.99319458 79.89808655 79.82653046 79.74854279 79.67372894 79.58831024 79.5031662 79.43788147 79.3477478 79.26921844 79.18582916 79.09677887 79.00870514 78.9206543 78.83283997 78.72781372 78.64667511 78.56212616 78.46379852 78.3603363 78.25707245 78.15799713 78.04486847 77.95733643 77.85897064 77.7598114 77.63258362 77.54478455 77.42340851 77.31121826 77.21882629 77.08872223 76.96497345 76.85969543 76.75071716 76.64395905 76.51867676 76.40805054 76.29418945 76.17870331 76.05678558 75.93326569 75.82054901 75.70578003 75.59799194 75.48257446 75.36853027 75.25279999 ' ...
        '75.14369202 75.04720306 74.93922424 74.82764435 74.73999786 74.6220932 74.52967834 74.43975067 74.3558197 74.26168823 74.17658234 74.08135223 74.00885773 73.92776489 73.8686142 73.79268646 73.73542023 73.65843201 73.60715485 73.55736542 73.50618744 73.46208954 73.41741943 73.37545776 73.34707642 73.2970047 73.27952576 73.25969696 73.23188782 73.22193909 73.20896912 73.20042419 73.19549561 73.20259857 73.18710327 73.17718506 73.19398499 73.18572235 73.19713593 73.19972229 73.2057724 73.22176361 73.23641968 73.25097656 73.25704956 73.2791214 73.29541779 73.31362152 73.3245163 73.33781433 73.34887695 73.36509705 73.37637329 73.38928223 73.394104 73.41706085 73.41575623 73.41947174 73.41564178 73.42372131 73.42650604 73.42048645 73.40737915 73.39608002 73.39985657 73.36956024 73.35043335 73.32711792 73.30153656 73.27507782 ' ...
        '73.23527527 73.20187378 73.1640625 73.10559082 73.05852509 73.02062225 72.94852448 72.89691162 72.82598877 72.76140594 72.6925354 72.61627197 72.54386902 72.4633255 72.38712311 72.29827118 72.20289612 72.10985565 72.01966858 71.93400574 71.83260345 71.73474884 71.64435577 71.53954315 71.4355545 71.34222412 71.24298096 71.13702393 71.03924561 70.94390869 70.83843994 70.75431061 70.6590271 70.57324982 70.46567535 70.38763428 70.31329346 70.22802734 70.15066528 70.07390594 70.0059433 69.93723297 69.86962128 69.81400299 69.75473785 69.69944 69.65460968 69.60478973 69.57077026 69.53845215 69.50830078 69.47615051 69.45072174 69.41143036 69.41501617 69.38804626 69.37522888 69.3706131 69.36448669 69.35473633 69.35134888 69.35194397 69.35053253 69.35657501 69.36151123 69.3699646 69.37532043 69.38295746 69.38018799 69.38594818 ' ...
        '69.39052582 69.38693237 69.39855194 69.39413452 69.39329529 69.39736176 69.40046692 69.39594269 69.37960815 69.37223816 69.35753632 69.34784698 69.32565308 69.31079865 69.27169037 69.25521851 69.22859955 69.19581604 69.15696716 69.11418152 69.0646286 69.0124054 68.94302368 68.89536285 68.83503723 68.74954987 68.6900177 68.60848999 68.52523804 68.43392944 68.33846283 68.25347137 68.14974213 68.05317688 67.93623352 67.83409882 67.72245026 67.62743378 67.496315 67.38817596 67.27067566 67.14241791 67.04450226 66.93115234 66.81707764 66.69415283 66.59643555 66.48141479 66.37368774 66.27920532 66.18244171 66.08525848 65.98954773 65.91075134 65.83126068 65.76298523 65.699646 65.62039185 65.57373047 65.53433228 65.4933548 65.46923828 65.45890045 65.43927765 65.43737793 65.45588684 65.47750854 65.51267242 65.5447998 65.60682678 ' ...
        '65.67066193 65.75051117 65.84163666 65.93188477 66.04772949 66.15973663 66.29424286 66.43045807 66.57746124 66.72846985 66.8900528 67.0597229 67.23049927 67.42399597 67.6175766 67.80469513 68.01676941 68.20780945 68.42935944 68.65080261 68.86573792 69.09558105 69.30453491 69.53399658 69.75791931 69.99984741 70.22730255 70.46781921 70.69098663 70.922966 71.16769409 71.39278412 71.62354279 71.86717224 72.09926605 72.31221008 72.53149414 72.77596283 73.00751495 73.23443604 73.45870972 73.66664886 73.87600708 74.0990448 74.31877899 74.52560425 74.73841095 74.94780731 75.15143585 75.36209106 75.56668091 75.76968384 75.97660065 76.17198944 76.37166595 76.566185 76.77316284 76.9651947 77.1563797 77.36677551 77.52526093 77.72644043 77.91631317 78.0979538 78.2907486 78.47547913 78.66103363 78.81775665 79.008255 79.18912506 ' ...
        '79.37380981 79.54987335 79.71382141 79.87474823 80.04330444 80.222229 80.38694 80.53785706 80.70701599 80.85150146 81.00467682 81.14680481 81.31011963 81.44314575 81.59181976 81.71955872 81.84540558 81.9768219 82.10731506 82.22736359 82.33470917 82.44639587 82.55760956 82.67293549 82.78011322 82.87081146 82.98069 83.06536102 83.15296173 83.24734497 83.32540894 83.40041351 83.49928284 83.57400513 83.65239716 83.72428894 83.7820816 83.84689331 83.9237442 83.9877243 84.04162598 84.08483887 84.15032959 84.20319366 84.25361633 84.30825806 84.35098267 84.40336609 84.44223022 84.49344635 84.53575134 84.58081818 84.60559082 84.65543365 84.69734192 84.72198486 84.77534485 84.80293274 84.83422852 84.86754608 84.89768219 84.94075775 84.97954559 85.01040649 85.03977203 85.07459259 85.1133194 85.14752197 85.1836319 85.20972443 ' ...
        '85.25067139 85.28784943 85.33876801 85.36787415 85.41105652 85.45690918 85.48828125 85.53574371 85.57645416 85.61994171 85.66038513 85.70484924 85.74578857 85.77751923 85.84509277 85.88433075 85.93545532 85.99902344 86.03552246 86.08994293 86.14849854 86.19638062 86.25053406 86.31912231 86.3723526 86.42734528 86.4838562 86.54356384 86.60150909 86.65626526 86.72640991 86.79051208 86.85541534 86.91303253 86.97261047 87.05241394 87.11038208 87.17385864 87.23622894 87.31227112 87.36764526 87.43730927 87.50634003 87.5791626 87.63571167 87.67684174 87.71913147 87.77886963 87.82814026 87.89093018 87.95244598 88.00263214 88.07735443 88.12843323 88.19202423 88.25540924 88.31761932 88.3996582 88.44203949 88.52120972 88.54782867 88.61445618 88.695755 88.75928497 88.82660675 88.86832428 88.94525146 88.97466278 89.06845093 89.11172485 ' ...
        '89.18243408 89.23883057 89.27902985 89.36208344 89.42584229 89.4772644 89.4962616 89.60730743 89.68258667 89.69719696 89.75504303 89.85098267 89.90934753 89.93687439 89.98715973 90.06778717 90.11766052 90.15943146 90.20957947 90.25852966 90.32542419 90.37812042 90.42051697 90.46782684 90.50889587 90.56157684 90.6002655 90.6783905 90.73164368 90.74632263 90.7889328 90.83533478 90.87421417 90.92508698 90.97057343 91.00671387 91.05755615 91.11167145 91.13705444 91.17247772 91.20696259 91.24681091 91.28185272 91.33029938 91.36231232 91.39044189 91.42987061 91.46746063 91.51140594 91.54249573 91.58332062 91.60549164 91.6408844 91.66033173 91.69680786 91.72689056 91.76985168 91.78871155 91.82097626 91.84898376 91.88096619 91.91405487 91.92575073 91.942276 91.96921539 91.99435425 92.01954651 92.05002594 92.07440948 92.09447479 ' ...
        '92.11947632 92.1490097 92.16281891 92.16786957 92.18585968 92.20928192 92.2218399 92.24040222 92.26519012 92.27818298 92.30388641 92.3152771 92.3204422 92.31829071 92.32732391 92.33988953 92.35968781 92.37432861 92.39045715 92.40263367 92.41378021 92.4131012 92.41864777 92.40274811 92.43130493 92.44656372 92.44972992 92.45584869 92.47770691 92.48907471 92.47631836 92.48418427 92.45848846 92.47573853 92.4813385 92.50304413 92.49761963 92.51661682 92.50815582 92.49766541 92.47605133 92.49501038 92.48459625 92.49263763 92.49817657 92.50387573 92.50324249 92.5092926 92.50778198 92.48586273 92.46723938 92.47615051 92.4691925 92.47801208 92.45809937 92.4717865 92.47431946 92.47219086 92.46012115 92.45272827 92.45436096 92.4391098 92.43005371 92.42163849 92.41927338 92.41372681 92.40403748 92.39609528 92.39881897 92.3931427 ' ...
        '92.37775421 92.36369324 92.35557556 92.35601807 92.33825684 92.32290649 92.32640076 92.31477356 92.30913544 92.29598236 92.28034973 92.27059174 92.25400543 92.24707794 92.23642731 92.22532654 92.2196579 92.21094513 92.19528198 92.17901611 92.16917419 92.1553421 92.14277649 92.12476349 92.11554718 92.10308838 92.07619476 92.0651474 92.04221344 92.02553558 92.00733185 91.98989868 91.96864319 91.93571472 91.93099976 91.89992523 91.88247681 91.84367371 91.83768463 91.81087494 91.78386688 91.75462341 91.73143768 91.69766235 91.67492676 91.6450882 91.60999298 91.57310486 91.5411377 91.5038147 91.48069 91.44316101 91.41111755 91.38153076 91.33493042 91.3137207 91.27536774 91.25015259 91.21031189 91.17913055 91.13317108 91.11029816 91.08074188 91.05236816 91.01248169 90.97839355 90.95274353 90.93445587 90.90096283 90.87190247 ' ...
        '90.83771515 90.81411743 90.79273224 90.75790405 90.74731445 90.71753693 90.68666077 90.67271423 90.64634705 90.62798309 90.60171509 90.59328461 90.57329559 90.55632019 90.52291107 90.51177979 90.4987793 90.4557724 90.44755554 90.42969513 90.41496277 90.39559174 90.3698349 90.35292053 90.32527161 90.30673218 90.28436279 90.26662445 90.23249817 90.21020508 90.1957016 90.17229462 90.15090942 90.12017822 90.09473419 90.07512665 90.0542984 90.02713776 89.9996109 89.98262024 89.95144653 89.932724 89.90937805 89.88514709 89.84238434 89.82737732 89.79507446 89.77999878 89.76173401 89.73158264 89.71594238 89.69621277 89.67094421 89.65577698 89.64019775 89.67469788 89.6295929 89.59020996 89.56161499 89.54589844 89.549263 89.54740906 89.51782227 89.23394775 89.53510284 89.55896759 89.55615997 89.55073547 89.53106689 89.54202271 ' ...
        '89.53275299 89.53089142 89.53311157 89.54411316 89.54206085 89.54760742 89.53630829 89.54151154 89.54817963 89.56202698 89.56989288 89.58320618 89.59082794 89.60124207 89.60192871 89.61695862 89.61381531 89.64015961 89.64865875 89.66396332 89.59565735 89.67657471 89.68978882 89.71472931 89.71508789 89.74038696 89.7443924 89.77059937 89.77246857 89.78136444 89.81036377 89.83132172 89.83512115 89.85497284 89.88894653 89.91806793 89.927948 89.9460144 89.95030975 90.03414154 90.05770874 90.08946228 90.13569641 90.15697479 90.19757843 90.24111938 90.27479553 90.32332611 90.36746216 90.40966034 90.47111511 90.53814697 90.58664703 90.64370728 90.6987381 90.7611084 90.81983948 90.87786865 90.95292664 91.01283264 91.08724976 91.16200256 91.22550201 91.30865479 91.37161255 91.43011475 91.53166199 91.61443329 91.68702698 91.77587891 ' ...
        '91.84634399 91.91460419 91.99917603 92.08599091 92.4690094 92.23532867 92.31419373 92.36880493 92.48977661 92.58241272 92.68034363 92.74388123 92.81894684 92.8480835 93.00656128 93.09334564 93.16712952 93.24908447 93.32971954 93.38384247 93.44754791 93.51271057 93.58227539 93.65794373 93.72895813 93.80783081 93.90419769 93.97052002 94.00820923 94.08702087 94.17269135 94.22885132 94.26335907 94.32074738 94.38609314 94.4606781 94.49905396 94.54891968 94.60634613 94.64665985 94.69678497 94.72119141 94.76540375 94.84472656 94.87411499 94.90869904 94.91552734 95.02567291 95.05130005 95.0617218 95.08707428 95.12136841 95.18096161 95.20835114 95.26077271 95.31324768 95.24243164 95.31649017 95.33213043 95.37034607 95.3497467 95.44138336 95.46305084 95.54429626 95.49285126 95.50930023 95.52745056 95.55277252 95.57763672 95.5746994 ' ...
        '95.61935425 95.62809753 95.65415192 95.67383575 95.69016266 95.73993683 95.71929932 95.65200806 95.74863434 95.77172089 95.79076385 95.80975342 95.79924011 95.81269836 95.79600525 95.85253906 95.85969543 95.8788681 95.88240814 95.89211273 95.85633087 95.93389893 95.95709229 95.95959473 95.9732666 95.9913559 96.00779724 96.00111389 95.97359467 96.04561615 96.07266235 96.07699585 96.08204651 96.09416962 96.10324097 96.11067963 96.12328339 96.14736176 96.16378784 96.16397095 96.19226074 96.19460297 96.19041443 96.21986389 96.22570038 96.23442078 96.24865723 96.25533295 96.2691803 96.28582001 96.29844666 96.31732941 96.33193207 96.32597351 96.34685516 96.35890961 96.35609436 96.38257599 96.38425446 96.39649963 96.40296173 96.41365051 96.42771912 96.43751526 96.44742584 96.46924591 96.4644928 96.49015045 96.49544525 96.4984436 ' ...
        '96.5171814 96.52970123 96.52970886 96.53836823 96.54520416 96.56124878 96.57141876 96.58508301 96.5880661 96.5965271 96.60583496 96.60457611 96.61803436 96.62784576 96.63153076 96.63488007 96.64323425 96.65463257 96.65771484 96.66408539 96.67010498 96.68500519 96.68318939 96.69364929 96.69239807 96.69776917 96.70032501 96.70918274 96.70522308 96.71974182 96.72277832 96.72622681 96.7278595 96.73191071 96.74620056 96.73015594 96.73605347 96.73822784 96.74816895 96.74681091 96.74525452 96.74979401 96.74887085 96.74751282 96.7565155 96.75432587 96.76676178 96.76010132 96.75580597 96.76885986 96.74667358 96.75808716 96.7668457 96.75964355 96.76075745 96.76089478 96.75899506 96.75810242 96.75399017 96.74794006 96.75228882 96.76428986 96.74419403 96.76173401 96.74399567 96.75410461 96.74710083 96.75049591 96.7419281 96.74295807 ' ...
        '96.72335815 96.72051239 96.72324371 96.70877075 96.71279907 96.69464111 96.69895935 96.69319153 96.68730927 96.6802597 96.65834045 96.66215515 96.64767456 96.6492691 96.62876892 96.62853241 96.61340332 96.6085434 96.60360718 96.59521484 96.57254791 96.57046509 96.56408691 96.55039215 96.53760529 96.53896332 96.5421524 96.51284027 96.50371552 96.47619629 96.49038696 96.45921326 96.45423889 96.44394684 96.42893982 96.40613556 96.39048004 96.38487244 96.36449432 96.36060333 96.32259369 96.30918121 96.31075287 96.28063202 96.2700119 96.24472809 96.24155426 96.21264648 96.19685364 96.17759705 96.17253876 96.13362885 96.11730957 96.09945679 96.07929993 96.0644455 96.03661346 96.01916504 95.99172974 95.97428131 95.9484024 95.9143219 95.89134216 95.8724823 95.84420013 95.8215332 95.80466461 95.77856445 95.75720215 95.7395401 ' ...
        '95.7170639 95.68741608 95.64994812 95.63354492 95.60683441 95.58201599 95.54484558 95.53107452 95.48703003 95.45365906 95.44187164 95.42011261 95.3870697 95.3636322 95.33061981 95.30052948 95.2689209 95.23551941 95.2329483 95.18374634 95.1556015 95.12630463 95.10705566 95.07904053 95.05292511 95.01486969 94.98602295 94.95334625 94.91742706 94.90718842 94.87397766 94.87151337 94.81179047 94.80744171 94.76264954 94.74499512 94.72035217 94.68456268 94.66879272 94.64775085 94.62791443 94.59812164 94.58963013 94.55793762 94.54058075 94.54006195 94.49376678 94.49230194 94.44867706 94.4683609 94.4330368 94.41706848 94.40872955 94.40100861 94.39322662 94.39581299 94.38399506 94.36936951 94.37811279 94.35961914 94.34237671 94.35838318 94.34779358 94.34355164 94.35460663 94.36057281 94.36808777 94.37918854 94.36625671 94.40037537 ' ...
        '94.40649414 94.42258453 94.43454742 94.42584991 94.45167542 94.46598816 94.47576141 94.49462128 94.51387787 94.54699707 94.54390717 94.56097412 94.62470245 94.61260986 94.6353302 94.65914154 94.70094299 94.70503998 94.73796844 94.77058411 94.81891632 94.82505035 94.84349823 94.88602448 94.90543365 94.93436432 94.94419861 94.97951508 94.99048615 95.03646088 95.06137848 95.08650208 95.11278534 95.16290283 95.1798172 95.19541931 95.2275238 95.26813507 95.27687073 95.33556366 95.3553772 95.37120819 95.39431763 95.42472076 95.48067474 95.48308563 95.50327301 95.51698303 95.56702423 95.59336853 95.60733032 95.63595581 95.66752625 95.69699097 95.72364807 95.74185944 95.76776886 95.78292847 95.80664825 95.79831696 95.87466431 95.8631897 95.88787842 95.93800354 95.960495 95.98361969 96.02910614 96.01715851 96.01180267 96.07139587 ' ...
        '96.11665344 96.13315582 96.12512207 96.14229584 96.17403412 96.17459106 96.22496033 96.22528076 96.24741364 96.26522064 96.24510193 96.31072235 96.30163574 96.36117554 96.36168671 96.37632751 96.4207077 96.42640686 96.42424774 96.41927338 96.47403717 96.48741913 96.43647766 96.49932098 96.51531219 96.48270416 96.50328827 96.52713776 96.57157898 96.59500885 96.57174683 96.61297607 96.62145233 96.62241364 96.62496185 96.62563324 96.6464386 96.66711426 96.64264679 96.695755 96.6735611 96.6488266 96.67318726 96.69515228 96.69896698 96.67957306 96.77649689 96.72780609 96.73007965 96.75299835 96.72789001 96.74753571 96.74455261 96.75188446 96.76950073 96.73303986 96.79911041 96.7674942 96.77040863 96.74492645 96.77453613 96.81715393 96.77880096 96.75482178 96.80744171 96.76735687 96.75525665 96.78754425 96.84836578 96.80109406 ' ...
        '96.8288269 96.81597137 96.75531006 96.84220886 96.81253052 96.83254242 96.80120087 96.84446716 96.82373047 96.8539505 96.83209229 96.88315582 96.91514587 96.86136627 96.87670135 96.87354279 96.8695755 96.84722137 96.89324188 96.88140869 96.840271 96.88365936 96.89234161 96.86974335 96.883461 96.91321564 96.89015198 96.90930939 96.89719391 96.93348694 96.94128418 96.89941406 96.94812012 96.8934021 96.92321777 96.95529938 96.92230988 96.97994995 97.02958679 97.00827026 96.86991882 96.99342346 96.97561646 97.01316071 97.04073334 97.01354218 97.00515747 96.99978638 97.01282501 97.02892303 97.00111389 97.11888123 97.04696655 97.03160858 96.98435211 97.00905609 97.02325439 97.00979614 97.04358673 97.04928589 97.08260345 97.13594818 97.09757233 97.08326721 97.0574646 96.97657776 97.14426422 97.08262634 97.07437134 97.14969635 ' ...
        '97.15396881 97.09155273 97.11902618 97.07439423 97.11641693 97.12839508 97.11425018 97.18803406 97.12484741 97.14348602 97.1350174 97.08718872 97.07507324 97.05367279 97.15688324 97.10042572 97.15305328 97.27479553 97.12377167 97.25523376 97.19148254 97.045578 97.17866516 97.25952148 97.27005005 97.3102951 97.11703491 97.3700943 97.15036774 97.16053772 97.17293549 97.20269775 97.08308411 97.21362305 97.14520264 97.13163757 97.13095093 97.22731781 97.10262299 97.07192993 97.16094971 97.20603943 97.20231628 97.23681641 97.20030975 97.27164459 97.31896973 97.2303772 97.33998108 97.21783447 97.05715942 97.25878143 97.11489105 97.35736084 97.14580536 97.2783432 97.1678772 97.36935425 97.23046112 97.35242462 97.4569397 97.32341766 97.26359558 97.19789886 97.00419617 97.248909 97.37186432 97.03797913 97.1308136 97.47163391 ' ...
        '97.25283051 97.13160706 97.3727417 97.28020477 97.39015198 97.29579163 97.48744965 97.18357086 97.49210358 97.17333984 97.45509338 97.48114014 97.46491241 97.26680756 97.52339935 97.69580078 97.34162903 97.3167572 97.57653809 97.52677155 97.45119476 97.28256226 97.43081665 97.32480621 97.36540985 97.58187866 97.62656403 97.32187653 97.78047943 97.39258575 97.55323029 97.52216339 97.66702271 97.50636292 97.40536499 97.88036346 97.66273499 97.67108154 97.7383728 97.67722321 97.49182129 97.62982178 97.21855927 97.41864777 97.49798584 97.72208405 97.64978027 97.38114929 97.42121887 97.25697327 97.31046295 97.18596649 97.72760773 97.67808533 97.323349 97.7088089 97.38858795 97.01068115 97.63228607 97.92421722 97.28749084 97.43376923 97.44519043 97.28979492 97.43378448 97.69015503 97.60973358 97.47635651 97.26073456 97.47332001 ' ...
        '97.69866943 97.36581421 97.45482635 97.59469604 97.31367493 97.66755676 97.71976471 97.18847656 97.30363464 97.69236755 97.53800964 97.07847595 97.33096313 97.62627411 97.74695587 97.49005127 97.26495361 97.5346756 97.54202271 97.23553467 97.20624542 97.22021484 97.45983124 96.99765778 97.33602142 97.33441925 97.37281036 97.61100006 97.251091 97.22003937 97.78437805 97.45584869 97.67803955 97.54198456 97.21856689 97.32628632 97.75337982 97.59938049 97.45331573 97.4876709 97.49082947 97.28364563 97.34896088 97.59655762 97.2833786 97.37126923 97.2928772 97.32495117 97.54949188 97.58509064 97.19487 97.26441193 97.28819275 97.43678284 97.46335602 97.43635559 97.13985443 97.35019684 97.37492371 97.1062088 97.52390289 97.28855133 97.2096405 97.31254578 97.15838623 97.42759705 97.31023407 97.63256073 97.26988983 97.35868835 ' ...
        '97.38369751 97.27246857 97.29234314 96.9828949 97.32010651 97.43400574 97.04299164 97.28318787 97.33040619 97.22203064 97.32463074 97.31648254 97.3187561 97.32598114 97.31873322 97.47094727 97.31807709 97.24798584 97.33850861 97.01079559 97.2098465 97.34111023 97.30012512 97.23156738 97.31069946 97.21403503 97.02301025 97.37724304 97.37509155 97.25099182 97.34400177 97.18562317 97.24117279 97.38725281 97.41925812 97.23506165 97.49681854 97.6280899 97.43814087 97.20707703 97.42910004 97.379776 97.49166107 97.1880188 97.41411591 97.47173309 97.44247437 97.29248047 97.14724731 97.24277496 97.41847229 97.50787354 97.29753113 97.61589813 97.43659973 97.36868286 97.35443115 97.19309235 97.36269379 97.27716064 97.44113922 97.39710236 97.43095398 97.24222565 97.43814087 97.34703827 97.32048035 97.45205688 97.52642059 97.40136719 ' ...
        '97.4077301 97.24396515 97.52377319 97.38771057 97.44522858 97.2486496 97.41119385 97.39602661 97.41474152 97.32705688 97.44197845 97.47572327 97.45608521 97.4598465 97.47141266 97.34037018 97.47746277 97.52492523 97.3189621 97.25332642 97.35757446 97.52709961 97.33539581 97.47676849 97.34651184 97.48503876 97.49621582 97.29174805 97.35721588 97.41160583 97.40141296 97.31038666 97.28612518 97.44396973 97.43501282 97.35029602 97.47299957 97.34294128 97.45291138 97.44682312 97.42211914 97.39661407 97.47484589 97.39637756 97.4519043 97.35686493 97.52465057 97.46086884 97.35301208 97.45166016 97.56977844 97.41710663 97.53536987 97.49916077 97.47402191 97.40512085 97.3325119 97.38694 97.51879883 97.47816467 97.51010895 97.34713745 97.38191223 97.46870422 97.32931519 97.46363831 97.3067627 97.43249512 97.57951355 97.44062042 ' ...
        '97.45075989 97.31021881 97.37919617 97.47946167 97.32669067 97.40522766 97.37520599 97.43915558 97.48588562 97.4847641 97.44768524 97.53305054 97.46075439 97.51260376 97.4644928 97.35935211 97.40348816 97.43526459 97.33416748 97.22324371 97.47724915 97.48075867 97.45357513 97.47172546 97.34958649 97.43045807 97.42876434 97.46013641 97.37792969 97.48532104 97.38038635 97.34514618 97.27296448 97.36579132 97.38276672 97.46217346 97.440979 97.4269104 97.33004761 97.39320374 97.47872925 97.34564209 97.37601471 97.39369965 97.37746429 97.40692139 97.35897064 97.41617584 97.33611298 97.36940002 97.35488129 97.2987442 97.41395569 97.38664246 97.4393158 97.28735352 97.38819885 97.27974701 97.29174805 97.30471802 97.43665314 97.37851715 97.16741943 97.40773773 97.36534882 97.45043945 97.40779877 97.27806854 97.31115723 97.32033539 ' ...
        '97.33337402 97.24858093 97.35255432 97.41111755 97.37585449 97.31648254 97.30594635 97.44767761 97.31610107 97.17858124 97.3094635 97.34815216 97.31161499 97.31880951 97.35956573 97.24982452 97.43188477 97.3793335 97.35820007 97.35305023 97.28327942 97.33579254 97.25605011 97.23701477 97.22596741 97.3175354 97.33917999 97.31861115 97.28508759 97.39574432 97.26243591 97.213974 97.25653076 97.30870056 97.29196167 97.29947662 97.37773132 97.2363739 97.19754028 97.2317276 97.25295258 97.30699921 97.13751984 97.24690247 97.22344971 97.27178955 97.11858368 97.31903839 97.28043365 97.23479462 97.32893372 97.22309113 97.16710663 97.13860321 97.24210358 97.24188232 97.24427032 97.24078369 97.25912476 97.22512054 97.19522858 97.34864807 97.23870087 97.13508606 97.18416595 97.21307373 97.20948792 97.2298584 97.18315125 97.24486542 ' ...
        '97.27326965 97.17977142 97.16812897 97.19807434 97.20848083 97.2131424 97.20417786 97.12815094 97.09634399 97.19680786 97.12395477 97.15174103 97.17073822 97.28811646 97.22111511 97.22161102 97.16574097 97.15423584 97.14603424 97.07635498 97.22200012 97.16159058 97.13661194 97.11470032 97.09643555 97.22024536 97.06977844 97.10881042 97.1457901 97.17793274 97.10966492 97.1444931 97.07310486 97.09574127 97.09825134 97.10128021 97.06035614 97.12509155 97.08774567 97.05396271 97.05184174 97.10852814 97.0615921 97.06515503 97.11453247 97.0760498 97.15263367 97.01238251 97.0750885 97.07988739 97.10865021 97.10852051 97.097229 97.02580261 97.07035828 97.05996704 97.12010956 97.02914429 97.01410675 97.02613068 97.00053406 97.07291412 97.02281952 96.94924164 96.98917389 96.98078156 96.99729919 97.03206635 97.01611328 96.99919891 ' ...
        '96.98188019 96.99073792 97.10466766 97.01676178 96.980896 96.94319153 96.95623779 97.00575256 96.97408295 97.01713562 96.89553833 96.89598846 96.94934845 97.04607391 96.92503357 96.99551392 97.11713409 97.04455566 96.94511414 96.87570953 96.88831329 96.92566681 96.98645782 96.99836731 96.96656799 96.94255829 96.89979553 97.05110168 96.90908051 96.97052002 96.85644531 96.84257507 96.90621185 96.93264008 96.8467865 96.85258484 96.94073486 96.91190338 96.85317993 96.89967346 96.87974548 96.8340683 96.98284149 96.8403244 96.84632874 96.8270874 96.918396 96.81520844 96.8249588 96.76850891 96.86071014 96.83592224 96.79779816 96.75402069 96.81904602 96.88798523 96.82182312 96.7822876 96.75613403 96.87359619 96.75658417 96.71847534 96.65896606 96.80744171 96.68965149 96.70448303 96.77871704 96.74490356 96.72930145 96.81651306 ' ...
        '96.70983887 96.65057373 96.85302734 96.62602234 96.58703613 96.76398468 96.7952652 96.68921661 96.6697998 96.6941452 96.56513977 96.63765717 96.61675262 96.61223602 96.5149231 96.70999908 96.75415802 96.51439667 96.63232422 96.72389984 96.67485046 96.58525848 96.50753021 96.63898468 96.67580414 96.63798523 96.64906311 96.45923615 96.56455231 96.5010376 96.60613251 96.51322174 96.59970856 96.40894318 96.51070404 96.63079071 96.53996277 96.42180634 96.47398376 96.54769135 96.55638885 96.44606018 96.40940094 96.43127441 96.51473999 96.4653244 96.51174164 96.48177338 96.37477875 96.53357697 96.47160339 96.38282776 96.34343719 96.50286865 96.4331131 96.33880615 96.37944794 96.41201782 96.37435913 96.3419342 96.28663635 96.31519318 96.3170929 96.25188446 96.28271484 96.29116058 96.29779816 96.22463226 96.27941132 96.32177734 ' ...
        '96.20890808 96.15974426 96.24245453 96.22954559 96.31349945 96.26872253 96.18925476 96.21910095 96.15934753 96.12549591 96.08351135 96.21170807 96.20350647 96.20722961 96.0120697 96.22862244 96.03026581 96.21738434 96.10123444 96.02101135 96.07485962 96.08019257 96.1355896 96.09983826 96.11022186 96.14694214 96.07468414 96.02126312 96.02829742 96.04869843 96.04079437 96.04425049 95.9227066 96.0376358 96.03672028 96.02877045 95.93720245 95.94442749 95.95262909 95.96374512 95.95678711 95.93332672 95.95251465 95.85111237 95.77935028 95.85689545 95.98001099 95.89498901 95.89816284 95.89929199 95.90680695 95.85890198 95.93624115 95.82254028 95.90253448 95.78826904 95.74546051 95.80948639 95.84238434 95.68530273 95.7988205 95.82559967 95.69288635 95.78782654 95.7074585 95.74115753 95.74089813 95.78771973 95.77196503 95.67991638 ' ...
        '95.68693542 95.73226929 95.72901154 95.58769226 95.72839355 95.70883179 95.70652008 95.73739624 95.61302948 95.71687317 95.66900635 95.61781311 95.7303009 95.58387756 95.59049988 95.56280518 95.6534729 95.65979004 95.6966629 95.64677429 95.63066101 95.57437134 95.60106659 95.52462769 95.61741638 95.63388824 95.46692657 95.39334106 95.61158752 95.54649353 95.4621582 95.45291901 95.46796417 95.41251373 95.44999695 95.42256165 95.30722809 95.30847168 95.45749664 95.4205246 95.39098358 95.42988586 95.36097717 95.45991516 95.38671112 95.38586426 95.38292694 95.25618744 95.41934967 95.2409668 95.32518005 95.41378784 95.19322968 95.32397461 95.45300293 95.37923431 95.31199646 95.15817261 95.29826355 95.34053802 95.25634766 95.40070343 95.18469238 95.31924438 95.34485626 95.1261673 95.29345703 95.24545288 95.20858765 95.18753052 ' ...
        '95.15520477 95.18460083 95.17351532 95.23673248 95.22276306 95.15615082 95.27978516 95.35715485 95.17247772 95.20363617 95.22425842 95.01769257 95.10657501 95.1211319 95.18775177 95.2095871 95.08804321 95.0105896 95.0861969 95.0774765 95.17205811 95.10842133 95.05356598 95.05511475 95.02124786 95.21632385 95.14342499 95.15950775 94.89559174 94.8559494 94.96403503 95.03279877 95.0173111 94.94915009 94.6940155 94.93553925 95.01661682 94.95995331 95.14910126 94.88235474 95.08104706 94.97801971 94.87652588 94.84629059 94.73635864 94.65324402 94.75193024 94.83861542 94.9212265 94.74856567 94.78020477 94.68683624 94.68912506 94.6830368 94.71559906 94.71665955 94.66044617 94.47966003 94.61631012 94.70793915 94.61447144 94.65055847 94.62998962 94.61663055 94.67369843 94.51709747 94.63457489 94.50946808 94.43893433 94.56564331 ' ...
        '94.45767975 94.366745 94.29187775 94.25344849 94.26409149 94.33625031 94.16417694 94.29163361 94.44961548 94.16389465 94.22981262 94.31324005 94.07240295 94.15406036 94.0582428 94.39959717 94.21628571 94.15556335 94.17989349 94.26927185 94.13197327 94.17930603 94.18520355 94.12439728 94.07823944 93.97956085 93.97031403 93.97894287 94.09164429 94.259552 93.93473816 93.95528412 94.05308533 94.06208038 94.04628754 94.12208557 93.99171448 93.91595459 93.84194946 94.10999298 93.80926514 93.78257751 94.2677536 93.87726593 94.06620026 93.94801331 94.07061005 93.94725037 93.87153625 93.5555191 93.75656891 93.58091736 93.91870117 93.79896545 93.82061768 93.62466431 93.74819183 93.61382294 93.81266785 93.72811127 93.46838379 93.63025665 93.86462402 93.59859467 93.52135468 93.60462189 93.40849304 93.57124329 93.56977081 93.42304993 ' ...
        '93.38822937 93.42237854 93.50040436 93.57227325 93.78512573 93.23265839 93.37052155 93.43884277 93.36426544 93.48442078 93.24790192 93.05767822 93.36094666 93.34833527 93.35797119 92.95619202 93.29449463 93.02810669 93.50819397 93.22693634 93.19306946 93.31012726 92.96398926 93.30632019 93.27200317 92.81056213 93.04980469 92.83290863 92.96051025 93.23028564 93.06028748 92.91693878 92.78466797 93.01611328 92.84871674 92.84898376 93.04431915 92.91447449 92.99596405 93.04238129 92.76832581 92.63018799 92.97127533 92.90303802 92.54432678 92.7166214 92.74329376 92.77323151 92.10668945 92.78590393 92.91843414 92.75415802 92.44852448 92.59649658 93.02107239 92.55963135 92.60413361 92.39022064 92.40192413 92.43000031 92.55173492 92.61141968 92.90033722 92.48669434 92.46252441 92.74711609 92.13474274 92.88085175 92.35328674 92.57566071 ' ...
        '92.17173767 92.33974457 92.33360291 92.6741333 92.19656372 91.87554932 92.22825623 92.04447937 92.30490875 92.30957794 92.38170624 92.45808411 91.89476013 92.06713104 91.80158997 92.28125763 91.91906738 91.54647827 92.16209412 91.991745 ' ...
        ], '%f');
end
function [firstNm, lastNm, reflectance] = est_embeddedCalciumCarbonate()
    firstNm = 2600;
    lastNm = 350.5;
    reflectance = sscanf([ ...
        '87.53474426 86.40686035 89.3077774 88.28106689 88.41397095 90.69145966 88.01985168 86.60562897 89.50769806 86.41947174 87.45314026 87.77427673 89.98425293 87.53643799 88.32161713 88.48269653 85.81436157 88.64633179 87.03351593 87.92841339 87.37445831 87.13070679 85.9115448 86.72233582 86.31233215 87.0517807 86.69959259 86.85243988 88.1628418 86.652771 88.23412323 86.92665863 87.55635071 87.34481049 86.77448273 86.84423065 86.56686401 86.14977264 87.03858185 87.09255981 86.43434906 87.42128754 87.05987549 85.79196167 86.72264862 86.45311737 85.24700165 86.67493439 86.3919754 85.92318726 85.50427246 85.44155121 85.90207672 86.13237 84.67666626 85.70617676 84.2746582 85.69213867 84.21329498 85.16587067 85.02928925 85.45765686 84.92066193 84.47988892 83.39086914 84.02259064 84.63204193 85.1977005 83.99310303 83.58071136 ' ...
        '84.41353607 83.74681854 83.24058533 82.95496368 82.47357941 82.9347229 83.01586914 82.36759186 82.63267517 81.86669922 81.84716034 81.51867676 82.36029053 81.72677612 81.84133148 81.69129181 81.06858826 81.11586761 81.29401398 80.77220154 80.35388947 80.56420135 80.66166687 79.72930908 80.16260529 79.67848969 79.86563873 79.38249969 78.99208832 78.52051544 78.77560425 78.47239685 78.39207458 78.37604523 77.85829163 77.77484894 77.64629364 77.8028183 77.51200104 77.53096008 77.55615997 77.13137054 76.84186554 77.05371094 76.49718475 76.81369019 77.2171402 76.28256989 76.56267548 76.59062958 76.36929321 76.09078979 76.00346375 75.58367157 75.95166779 76.15717316 76.08045959 76.05570221 76.18531036 75.92848206 75.71569061 75.55169678 75.67638397 75.71062469 75.96003723 76.06292725 75.73004913 75.81455994 75.72199249 75.83088684 ' ...
        '76.01138306 76.20282745 76.63115692 76.19277191 75.9720993 76.24317932 76.43028259 76.48600006 76.60072327 76.56014252 76.67115021 76.88913727 76.68939209 76.96185303 77.15263367 77.11630249 77.19846344 77.24176788 76.99445343 77.50184631 77.39354706 77.5419693 77.64048004 77.54328918 77.758255 77.8136673 78.05257416 78.10224152 77.87651062 77.97031403 78.2358551 78.19548798 78.299263 78.0572052 78.42190552 78.30224609 78.56337738 78.40828705 78.9440918 78.6216507 78.46387482 78.74627686 78.66175079 78.77604675 78.79051208 78.79140472 78.74822998 79.03335571 78.94852448 78.86997986 79.14440155 79.02427673 78.9581604 78.95832825 79.33744049 79.18704987 79.31487274 79.2903595 79.3277359 79.20896912 79.29219818 79.61077881 79.36933136 79.3434906 79.63222504 79.49575043 79.53113556 79.4619751 79.66121674 79.61055756 ' ...
        '79.56144714 79.75097656 79.6469574 79.73123932 79.89323425 79.6978302 80.10430908 79.99420166 79.90262604 79.98136139 80.03489685 80.1911087 80.08860779 80.36277008 80.22438049 80.44126892 80.29159546 80.56935883 80.62438202 80.60781097 80.51068878 80.70711517 80.85862732 81.03153992 80.96616364 80.91677856 81.09617615 81.15805817 81.39431763 81.43845367 81.31958008 81.32622528 81.54693604 81.55886078 81.74140167 81.67448425 81.86224365 81.81459808 81.92223358 82.15328217 82.18872833 82.15235138 82.43202972 82.57798004 82.56198883 82.73036194 82.69862366 82.78526306 82.99485779 83.05414581 83.13980865 83.25738525 83.34645081 83.41996002 83.45128632 83.52639771 83.65258789 83.80863953 83.80275726 83.96694946 84.17285156 84.17590332 84.26334381 84.46029663 84.54614258 84.49253082 84.54199219 84.68460083 84.70355988 84.80504608 ' ...
        '84.89482117 84.98822784 85.18151855 85.07640839 85.17942047 85.26598358 85.53755188 85.52626038 85.68864441 85.78182983 85.74069214 85.68779755 85.84293365 85.94773102 86.08209991 86.19511414 86.17312622 86.20804596 86.31331635 86.36779785 86.32567596 86.40679932 86.520401 86.74046326 86.81565094 86.73605347 86.89382935 87.0617218 87.0128479 87.1526413 87.11380768 87.18267059 87.27772522 87.16609955 87.37631226 87.45983124 87.41930389 87.38568115 87.56426239 87.61224365 87.73222351 87.6969223 87.67554474 87.81333923 87.84600067 87.80511475 87.86097717 88.0332489 88.07061768 88.17976379 88.13564301 88.15348816 88.24832153 88.32420349 88.39867401 88.30820465 88.55180359 88.4243927 88.50469971 88.55535126 88.63646698 88.57091522 88.7865448 88.78128815 88.91138458 88.79151917 88.79137421 88.93881989 89.1216507 89.02688599 ' ...
        '89.07199097 89.18044281 89.21635437 89.19322205 89.13275909 89.17404175 89.20752716 89.37608337 89.32905579 89.42742157 89.47605133 89.32971191 89.46582031 89.49406433 89.5599823 89.5327301 89.56314087 89.62802124 89.62863922 89.60791779 89.76981354 89.84380341 89.67915344 89.74216461 89.78016663 89.85182953 89.94289398 89.94441223 89.85621643 89.93992615 89.89091492 89.91028595 89.91471863 90.00273132 90.0877533 90.08262634 90.07976532 90.04158783 90.20995331 90.11979675 90.14715576 90.22400665 90.09587097 90.14765167 90.12646484 90.24776459 90.32544708 90.347229 90.25577545 90.22537231 90.27749634 90.33763123 90.23673248 90.31783295 90.39257813 90.41397858 90.19350433 90.35721588 90.28227234 90.18807983 90.34085846 90.40614319 90.36427307 90.26898193 90.35540771 90.39256287 90.40737915 90.35818481 90.33773804 90.42609406 ' ...
        '90.25727081 90.36335754 90.42945099 90.32704926 90.39814758 90.37906647 90.31408691 90.26280975 90.29782104 90.32110596 90.23567963 90.2640686 90.19672394 90.2504425 90.24228668 90.11651611 90.12451172 90.1359787 90.12173462 90.02466583 89.87198639 89.83637238 89.88716888 89.84886169 89.76205444 89.83223724 89.64994812 89.60895538 89.58502197 89.57791901 89.47839355 89.44677734 89.30156708 89.25018311 89.29755402 89.08721161 89.03871918 89.07202148 88.88639832 88.83730316 88.75354767 88.61928558 88.55406952 88.4622345 88.30544281 88.31001282 88.17860413 88.05195618 87.98684692 87.83589172 87.69015503 87.61470032 87.4931488 87.31048584 87.22606659 87.04151917 86.95638275 86.93070984 86.76091003 86.61247253 86.48867798 86.31946564 86.16236115 86.04940796 85.93427277 85.86264038 85.63175201 85.53700256 85.56134796 85.39804077 ' ...
        '85.21498108 85.12576294 84.98020172 84.91095734 84.73607635 84.59455872 84.49594879 84.40394592 84.33190918 84.24217987 84.09272766 83.93809509 83.86058044 83.80324554 83.71191406 83.6907196 83.59037781 83.50907898 83.33202362 83.33154297 83.25210571 83.13739777 83.12147522 83.11309052 83.09889984 82.93338776 82.93907928 82.86302185 82.95240784 82.9050827 82.77780151 82.74365234 82.78012085 82.76528931 82.70294952 82.73821259 82.72720337 82.72882843 82.6705246 82.74737549 82.73820496 82.74797821 82.79176331 82.77275848 82.85098267 82.84000397 82.82730865 82.95748901 82.97161865 82.9533844 83.0947876 83.100914 83.13851929 83.13114929 83.23079681 83.30623627 83.25946045 83.34957886 83.30623627 83.4469986 83.4643631 83.459198 83.61373901 83.64640808 83.65348816 83.69360352 83.85667419 83.87931824 83.83447266 83.84722137 ' ...
        '84.01515198 83.98762512 84.07952118 84.08763123 84.10255432 84.1735611 84.1992569 84.23976135 84.28542328 84.35599518 84.37464142 84.38334656 84.46359253 84.45574188 84.5495224 84.49000549 84.52236176 84.62063599 84.63193512 84.62435913 84.61798096 84.72229004 84.75180054 84.71511841 84.71401978 84.79693604 84.79302216 84.83274841 84.89167023 84.92601776 84.99441528 84.92450714 84.91577148 84.95057678 84.96694946 85.01973724 85.02019501 85.07206726 85.03071594 85.066185 85.14160156 85.16734314 85.1607666 85.17398834 85.14203644 85.21193695 85.22163391 85.28133392 85.26206207 85.33640289 85.32772827 85.33740234 85.35360718 85.42539978 85.31986237 85.47309113 85.44979095 85.51300049 85.51928711 85.51560211 85.64785767 85.5738678 85.665802 85.675354 85.67926788 85.71713257 85.79798889 85.73822784 85.81739044 85.8317337 ' ...
        '85.86244965 85.92098999 85.92817688 85.93673706 85.96001434 86.15744019 86.15245056 86.10897064 86.15223694 86.17549896 86.17783356 86.26343536 86.31243896 86.34450531 86.34353638 86.39936066 86.40261078 86.53767395 86.52252197 86.64405823 86.49234772 86.67004395 86.6280365 86.657547 86.78985596 86.80537415 86.85500336 86.7739563 86.95792389 87.01773071 86.95702362 86.94934845 87.06889343 87.09848785 87.04582214 87.09645844 87.11288452 87.14451599 87.2148819 87.15031433 87.24355316 87.37102509 87.37593079 87.28328705 87.30544281 87.37271881 87.39954376 87.39713287 87.5138092 87.48682404 87.4650116 87.60068512 87.50377655 87.60074615 87.58987427 87.54795074 87.60093689 87.64028931 87.63069153 87.66379547 87.74750519 87.71175385 87.71832275 87.74176025 87.73033905 87.77557373 87.82320404 87.77099609 87.80130768 87.90545654 ' ...
        '87.86077118 87.82936096 87.92684174 87.91685486 87.96495056 87.8638382 87.87289429 87.98817444 87.97261047 88.0071106 87.99069214 88.07544708 88.06924438 88.12546539 88.04717255 88.09039307 88.05045319 88.15406799 88.16100311 88.18920898 88.04430389 88.10875702 88.16921234 88.18858337 88.212677 88.2285614 88.30224609 88.27425385 88.24410248 88.39265442 88.35398102 88.35150146 88.42825317 88.39354706 88.32923126 88.41249084 88.36113739 88.43079376 88.34591675 88.43495941 88.33760834 88.34380341 88.45283508 88.34711456 88.41436768 88.32736206 88.41220093 88.450737 88.45145416 88.44028473 88.46297455 88.37322235 88.48705292 88.38088989 88.35373688 88.43696594 88.40853882 88.40036011 88.36950684 88.43412781 88.40016174 88.40545654 88.4270401 88.40735626 88.44841003 88.38400269 88.40066528 88.42531586 88.34448242 88.46573639 ' ...
        '88.53384399 88.4226532 88.45072937 88.48316193 88.52640533 88.53993988 88.5838623 88.52424622 88.5968399 88.66614532 88.66877747 88.71187592 88.67090607 88.77474213 88.78759766 88.85629272 88.87714386 89.01546478 89.02055359 89.09102631 89.06983948 89.12284088 89.1582489 89.13539886 89.2832489 89.32541656 89.41275787 89.39403534 89.4992981 89.53992462 89.63508606 89.71845245 89.72940063 89.82309723 89.84545898 89.93161774 89.95410156 90.04197693 90.05860901 90.22420502 90.21591187 90.28305054 90.36521149 90.40763092 90.44731903 90.54740906 90.59645081 90.65471649 90.62986755 90.78222656 90.82335663 90.82292175 90.8446579 90.94590759 90.89499664 91.06164551 91.13285828 91.0958252 91.09434509 91.1987915 91.2263031 91.22370148 91.30786896 91.36550903 91.3862915 91.44069672 91.41655731 91.43263245 91.57463074 91.53903961 ' ...
        '91.54249573 91.5476532 91.53436279 91.61511993 91.61035156 91.61962128 91.67485809 91.68073273 91.69954681 91.79359436 91.78829193 91.72895813 91.73664093 91.85601807 91.79340363 91.78617096 91.80286407 91.86502075 91.83576965 91.82924652 91.87070465 91.92630005 91.9021759 92.00106049 91.90072632 91.95323181 91.87506866 91.9410553 91.98412323 91.98220062 91.96562958 91.96479797 92.06134033 92.07078552 92.02314758 92.07348633 92.07576752 92.05727386 92.17762756 92.10514069 92.18516541 92.12969971 92.16624451 92.17006683 92.16064453 92.22441101 92.21598816 92.31402588 92.28759766 92.31000519 92.32498169 92.36484528 92.35900879 92.37832642 92.34690094 92.44230652 92.51017761 92.52255249 92.51930237 92.49929047 92.51623535 92.59147644 92.62197876 92.64781189 92.58950043 92.69391632 92.72220612 92.78736115 92.68481445 92.71954346 ' ...
        '92.75930786 92.81684875 92.85231781 92.88030243 92.92652893 92.93605804 92.94309998 92.96012878 92.94889069 92.99353027 93.04483795 93.08969879 93.00720978 93.17704773 93.16954803 93.21897125 93.14051056 93.1887207 93.2004776 93.26127625 93.29884338 93.25509644 93.28920746 93.26595306 93.32515717 93.38014984 93.3021698 93.39563751 93.37242126 93.39115143 93.41011047 93.38111877 93.35133362 93.38613892 93.35746002 93.41420746 93.35361481 93.36963654 93.40309143 93.36908722 93.50014496 93.40413666 93.43960571 93.36724091 93.42328644 93.40441132 93.45330811 93.39625549 93.40962982 93.42695618 93.43963623 93.42370605 93.35264587 93.41284943 93.40851593 93.34636688 93.44717407 93.44495392 93.41512299 93.35485077 93.36048126 93.40563202 93.36681366 93.40096283 93.40080261 93.43549347 93.3453598 93.36704254 93.37236023 93.34159851 ' ...
        '93.3915863 93.36813354 93.34452057 93.32004547 93.34421539 93.36463928 93.29259491 93.33955383 93.35973358 93.3481369 93.34099579 93.37111664 93.28853607 93.29721832 93.30047607 93.28382111 93.35578918 93.31503296 93.34233093 93.31850433 93.23994446 93.28903198 93.29393768 93.23547363 93.28662109 93.27529144 93.28354645 93.36425781 93.33552551 93.24639893 93.25878906 93.30874634 93.30119324 93.24324036 93.2444458 93.32021332 93.258461 93.21591187 93.26519012 93.20489502 93.23538208 93.19384766 93.2075119 93.20440674 93.18744659 93.20824432 93.17098236 93.16962433 93.21323395 93.25339508 93.2635498 93.15582275 93.1547699 93.16262817 93.18254852 93.14857483 93.13568115 93.17015076 93.19326782 93.09039307 93.16986084 93.11821747 93.06687927 93.09719849 93.07993317 93.05470276 93.10766602 93.01836395 93.07013702 93.09658813 ' ...
        '93.06815338 93.03453064 93.05480957 93.02639771 93.0542984 93.02476501 93.02940369 93.03874207 93.02797699 92.98184204 93.00579071 92.93520355 93.00478363 92.98364258 93.00254822 92.99488068 92.97036743 92.95902252 92.94432068 92.94561768 92.90563202 92.89797211 92.92520905 92.89463043 92.96554565 92.94993591 92.88410187 92.89589691 92.88050079 92.90016174 92.88906097 92.86058044 92.87787628 92.88046265 92.82662964 92.83154297 92.80776978 92.82308197 92.80947113 92.82782745 92.82753754 92.81674957 92.77654266 92.78039551 92.73693085 92.71503448 92.73721313 92.74761963 92.74623871 92.71166229 92.70040894 92.69560242 92.66202545 92.68377686 92.6844101 92.67195892 92.68684387 92.70702362 92.66651154 92.66413116 92.63884735 92.64958191 92.65072632 92.58437347 92.56533051 92.56706238 92.57720947 92.54560852 92.55252838 92.55711365 ' ...
        '92.53297424 92.52912903 92.47341919 92.48865509 92.53486633 92.47410583 92.45311737 92.48985291 92.42066193 92.45257568 92.42340088 92.38026428 92.38952637 92.39291382 92.37359619 92.35406494 92.31874084 92.32401276 92.32730103 92.32112885 92.28707886 92.28221893 92.25887299 92.2304306 92.21133423 92.24262238 92.1567688 92.20388794 92.13948059 92.13896179 92.11605835 92.06334686 92.08621216 92.0915451 92.11338043 92.04042816 92.00500488 91.99680328 91.97241211 91.97257996 91.95347595 91.92936707 91.88004303 91.86556244 91.82217407 91.82064819 91.84088135 91.77574158 91.77062225 91.72146606 91.71664429 91.71649933 91.6424408 91.64724731 91.64877319 91.6198349 91.57751465 91.48983002 91.54493713 91.47966766 91.44013214 91.42845154 91.42371368 91.3813858 91.35309601 91.33768463 91.31164551 91.29914856 91.23152161 91.28926086 ' ...
        '91.20436096 91.17073059 91.19503784 91.13768005 91.099823 91.09646606 91.07254791 91.06233978 91.00158691 91.0239563 90.99027252 90.95983887 90.94191742 90.9046402 90.92399597 90.90566254 90.89595795 90.90006256 90.88343048 90.86375427 90.86366272 90.85192871 90.81791687 90.81051636 90.85202789 90.82437897 90.82331085 90.82794952 90.83144379 90.83711243 90.82342529 90.82492828 90.81239319 90.77268219 90.83302307 90.74956512 90.78253174 90.80885315 90.85760498 90.83351898 90.8162384 90.85144043 90.83010101 90.84346771 90.85597992 90.81867981 90.86618805 90.82525635 90.83953857 90.84817505 90.83563995 90.85250092 90.83704376 90.85454559 90.85637665 90.87595367 90.89476776 90.87897491 90.84030914 90.84960938 90.8542099 90.84689331 90.8572464 90.85146332 90.82788849 90.86934662 90.81309509 90.86499786 90.83348846 90.84416962 ' ...
        '90.83714294 90.8727951 90.83253479 90.83983612 90.8568573 90.86588287 90.8306427 90.82827759 90.84290314 90.8038559 90.83881378 90.86019897 90.84932709 90.80606079 90.83408356 90.84028625 90.81234741 90.80997467 90.83474731 90.79706573 90.82077026 90.82429504 90.79766083 90.82180023 90.85136414 90.85842133 90.82593536 90.82176208 90.83558655 90.82311249 90.86569214 90.83956146 90.83088684 90.8901062 90.8508606 90.82997131 90.82103729 90.84590912 90.81726074 90.80727386 90.84039307 90.85448456 90.8174057 90.8301239 90.85910797 90.82588196 90.85170746 90.83283234 90.82157898 90.8247757 90.8682251 90.83237457 90.84410858 90.83694458 90.84290314 90.86364746 90.86387634 90.88487244 90.85266113 90.89043427 90.84051514 90.83996582 90.83192444 90.83281708 90.87708282 90.888237 90.87459564 90.86548615 90.87927246 90.87717438 ' ...
        '90.896698 90.87784576 90.87260437 90.88018799 90.91338348 90.88417053 90.84894562 90.91208649 90.82648468 90.89593506 90.88786316 90.85770416 90.92085266 90.92185211 90.92462921 90.92761993 90.92506409 90.93010712 90.9331665 90.96279907 90.91930389 90.9434433 90.9661026 90.88290405 90.91536713 90.93874359 90.9430542 90.98553467 90.99359131 90.99154663 90.97260284 91.01459503 91.07038116 91.03885651 91.02909851 91.04673004 91.07595062 91.07497406 91.06922913 91.09490967 91.11688995 91.10591888 91.11915588 91.13357544 91.1344223 91.14761353 91.19809723 91.16155243 91.19060516 91.23836517 91.19702148 91.19779205 91.22608948 91.2735672 91.28710175 91.30458069 91.29307556 91.32870483 91.32522583 91.34075928 91.29437256 91.36860657 91.39059448 91.43623352 91.43112946 91.43824768 91.45570374 91.44132233 91.44239807 91.45966339 ' ...
        '91.46231079 91.53915405 91.49724579 91.51266479 91.55382538 91.50648499 91.54727173 91.53288269 91.54602814 91.53489685 91.51255035 91.55554962 91.54936218 91.55056763 91.61019135 91.57204437 91.56858826 91.57323456 91.58756256 91.60684967 91.58383179 91.58431244 91.58150482 91.55809021 91.60869598 91.56096649 91.65059662 91.60256958 91.59908295 91.58453369 91.62175751 91.60861206 91.57939148 91.59856415 91.64897919 91.62025452 91.59561157 91.63004303 91.61929321 91.63909912 91.62342834 91.65893555 91.62774658 91.66432953 91.64993286 91.68997955 91.69846344 91.72649384 91.71508789 91.7347641 91.77454376 91.79586792 91.79528046 91.84849548 91.82242584 91.87719727 91.90579987 91.89141846 91.95856476 91.9713974 91.99134064 92.03411865 92.05300903 92.09037781 92.13356781 92.13339233 92.20227051 92.17958069 92.28316498 92.26091766 ' ...
        '92.32361603 92.32303619 92.33979034 92.37817383 92.42446136 92.43524933 92.47267914 92.52776337 92.5289917 92.55264282 92.59288025 92.60481262 92.66973114 92.68252563 92.67909241 92.7326355 92.75934601 92.81426239 92.81552887 92.80758667 92.79751587 92.84799957 92.82115936 92.84941864 92.90015411 92.93218231 92.90641022 92.92475128 92.94754791 92.98475647 92.97994995 93.00576019 93.00032043 93.03361511 93.01451111 93.07304382 93.02944183 93.06895447 93.1076355 93.07252502 93.12609863 93.13580322 93.12944794 93.11697388 93.16468811 93.16611481 93.14509583 93.20929718 93.20181274 93.19915009 93.19696808 93.1953125 93.24253082 93.2305603 93.24564362 93.3037262 93.26403809 93.26964569 93.29663849 93.28137207 93.30445862 93.35121155 93.32379913 93.36293793 93.36296082 93.35288239 93.39578247 93.38994598 93.36915588 93.35755157 ' ...
        '93.41140747 93.43917084 93.45032501 93.47018433 93.45236206 93.49351501 93.46203613 93.48353577 93.46336365 93.47499847 93.51499939 93.55963898 93.55280304 93.55434418 93.52671814 93.56511688 93.51876068 93.53343201 93.57521057 93.58232117 93.59148407 93.60001373 93.56479645 93.54666138 93.56774902 93.60063171 93.61475372 93.61156464 93.63401794 93.63878632 93.67392731 93.64742279 93.64317322 93.64917755 93.64178467 93.67551422 93.66810608 93.69135284 93.69246674 93.70358276 93.73031616 93.6775589 93.72319794 93.68593597 93.72311401 93.72328949 93.7177124 93.74130249 93.72949219 93.72846985 93.73471832 93.75305939 93.74757385 93.73633575 93.77925873 93.75146484 93.76850128 93.7541275 93.76428223 93.79884338 93.77165222 93.75576019 93.78027344 93.78039551 93.776474 93.76815033 93.80047607 93.7973175 93.78471375 93.78731537 ' ...
        '93.80290985 93.8318634 93.79243469 93.79872131 93.83214569 93.82702637 93.83486176 93.81388092 93.8407135 93.81726837 93.84415436 93.83139801 93.83276367 93.81603241 93.83687592 93.85617828 93.8411026 93.85075378 93.87109375 93.83856964 93.85878754 93.84941864 93.83984375 93.85048676 93.86972046 93.86456299 93.86894989 93.86551666 93.86065674 93.85971832 93.84067535 93.87028503 93.84722137 93.86723328 93.85173798 93.82968903 93.85480499 93.84407043 93.85240936 93.84819031 93.8515625 93.85995483 93.82658386 93.87081146 93.80349731 93.84429169 93.78993225 93.8252182 93.85848999 93.82376862 93.82608032 93.83061218 93.84350586 93.83568573 93.82302856 93.83338165 93.78832245 93.82501221 93.82735443 93.80540466 93.79156494 93.81733704 93.82167816 93.79309082 93.80858612 93.79921722 93.81689453 93.80886841 93.80225372 93.80129242 ' ...
        '93.79769897 93.79407501 93.81671906 93.8146286 93.78406525 93.80047607 93.79148102 93.81536865 93.78411102 93.80352783 93.83213806 93.81720734 93.81738281 93.81510925 93.82056427 93.82351685 93.83838654 93.81524658 93.84960175 93.84265137 93.86143494 93.85818481 93.86148071 93.86725616 93.86380005 93.86856842 93.86206055 93.89313507 93.8799057 93.90650177 93.91210938 93.89539337 93.91096497 93.91017914 93.89579773 93.94236755 93.93850708 93.94406128 93.9576416 93.94374847 93.94167328 93.93701935 93.95366669 93.96403503 93.94883728 93.96121216 94.03358459 93.99098969 94.00249481 93.98392487 93.98229218 93.98908997 93.99172974 94.00977325 94.01011658 93.99602509 94.02093506 94.02970123 94.02393341 93.99539185 94.00518036 94.03006744 94.02464294 94.03025055 94.03668213 94.05511475 94.04390717 94.04445648 94.06364441 94.04927063 ' ...
        '94.06880951 94.05678558 94.08281708 94.07593536 94.08089447 94.07769012 94.08840179 94.10951233 94.09803772 94.09960175 94.1244278 94.12227631 94.12704468 94.10198212 94.12486267 94.13986969 94.11653137 94.14177704 94.15249634 94.15380096 94.14107513 94.12329102 94.15507507 94.16370392 94.17623138 94.1827774 94.16646576 94.204422 94.19985962 94.18458557 94.2035141 94.21932983 94.20475769 94.22028351 94.23982239 94.23742676 94.23974609 94.24668884 94.24016571 94.24099731 94.24820709 94.27177429 94.26046753 94.27774811 94.27384186 94.28813934 94.29203033 94.287117 94.29056549 94.30311584 94.31087494 94.32595062 94.32265472 94.32379913 94.32633209 94.33271027 94.32876587 94.34630585 94.34384918 94.359375 94.38215637 94.38728333 94.3658371 94.38249969 94.35605621 94.39033508 94.37028503 94.39308167 94.4023819 94.41172791 ' ...
        '94.4126358 94.4252243 94.39971161 94.37994385 94.40267944 94.40281677 94.44711304 94.41970825 94.44009399 94.43029022 94.42540741 94.42221832 94.43096924 94.41397095 94.4357605 94.42567444 94.43704224 94.46491241 94.43427277 94.44303894 94.45510864 94.4431839 94.4320755 94.42765045 94.46357727 94.43994904 94.45250702 94.45249176 94.45587158 94.43790436 94.45691681 94.44475555 94.45018768 94.42974091 94.44128418 94.44464111 94.44087982 94.44033813 94.44591522 94.4469986 94.43543243 94.43874359 94.44625854 94.42378998 94.43540955 94.43126678 94.42936707 94.45001984 94.44472504 94.45295715 94.44187927 94.42141724 94.4285202 94.42507172 94.43393707 94.4228363 94.44101715 94.44365692 94.43265533 94.4462204 94.43029785 94.41996765 94.43281555 94.42736816 94.4285965 94.42041016 94.44181824 94.43908691 94.42463684 94.43537903 ' ...
        '94.44036865 94.41925812 94.421875 94.42576599 94.44258881 94.44959259 94.43013 94.43364716 94.42622375 94.41904449 94.42388153 94.4401474 94.44320679 94.43965149 94.43358612 94.44758606 94.44812775 94.41887665 94.4367981 94.42169952 94.43069458 94.44487 94.45883942 94.43709564 94.44259644 94.46356201 94.43736267 94.45504761 94.44844818 94.44184113 94.47248077 94.46717834 94.46657562 94.45187378 94.46837616 94.46643829 94.45307922 94.45762634 94.47658539 94.4677887 94.47180939 94.50238037 94.47896576 94.47544861 94.48131561 94.49189758 94.49461365 94.50020599 94.50210571 94.50196838 94.51139832 94.50354767 94.51933289 94.51410675 94.52232361 94.5112915 94.53107452 94.53317261 94.52701569 94.51900482 94.54364777 94.53938293 94.53775024 94.55242157 94.53941345 94.54264069 94.54051208 94.5440979 94.55399323 94.55297852 ' ...
        '94.56161499 94.570755 94.55661011 94.5697937 94.54573059 94.54055786 94.54425049 94.55944061 94.56263733 94.56391907 94.56044769 94.56811523 94.53695679 94.54196167 94.53575134 94.55314636 94.55875397 94.56296539 94.56204987 94.56902313 94.5694046 94.54380798 94.5479126 94.55354309 94.54883575 94.56698608 94.55352783 94.56246185 94.56731415 94.57780457 94.54556274 94.5553894 94.55189514 94.54766083 94.55537415 94.55810547 94.54573059 94.56905365 94.56333923 94.54433441 94.56959534 94.55921936 94.5561676 94.55175018 94.5530777 94.55111694 94.55254364 94.56175995 94.54109192 94.54895782 94.54827881 94.5517807 94.55047607 94.54187012 94.5415802 94.5537796 94.54751587 94.53888702 94.54908752 94.54908752 94.55158997 94.54689789 94.53072357 94.53377533 94.5431366 94.53986359 94.53369141 94.56053925 94.54924774 94.53937531 ' ...
        '94.53739166 94.52468872 94.55038452 94.53032684 94.55072021 94.54853821 94.54103851 94.53520966 94.51179504 94.53004456 94.51793671 94.51545715 94.52010345 94.52186584 94.53629303 94.5280304 94.53772736 94.5219574 94.50892639 94.50556183 94.52353668 94.51236725 94.51654816 94.52197266 94.51543427 94.50952148 94.50336456 94.50119019 94.50193024 94.50629425 94.50082397 94.50507355 94.51120758 94.50917053 94.49211884 94.49780273 94.49043274 94.50192261 94.4908905 94.49801636 94.50036621 94.49285889 94.49069977 94.49230194 94.48181152 94.47621155 94.48361969 94.48729706 94.49301147 94.49178314 94.50971985 94.49899292 94.48736572 94.47793579 94.48731995 94.48826599 94.47775269 94.49117279 94.49066162 94.48667145 94.49137878 94.49800873 94.49851227 94.50074768 94.49430084 94.50273895 94.49936676 94.49636078 94.51058197 94.51299286 ' ...
        '94.49990845 94.50289917 94.48707581 94.50865173 94.50643921 94.50469208 94.51107025 94.50177765 94.49617004 94.5052948 94.51239777 94.50743866 94.50046539 94.48957825 94.4954834 94.49692535 94.50279236 94.49492645 94.50361633 94.50074005 94.5059967 94.51612854 94.49707031 94.50157166 94.50365448 94.50122833 94.49964905 94.50938416 94.5165329 94.50761414 94.5082016 94.4970932 94.50056458 94.48134613 94.47811127 94.48599243 94.48944092 94.50589752 94.49253082 94.49279022 94.49351501 94.47473145 94.48451996 94.4848175 94.48677063 94.48413849 94.48924255 94.49277496 94.48406219 94.49066925 94.46828461 94.48355865 94.46681976 94.46665192 94.48200226 94.48665619 94.4859314 94.47907257 94.46382904 94.46357727 94.46434021 94.45402527 94.46957397 94.46937561 94.46784973 94.45616913 94.46003723 94.44091034 94.4469986 94.45222473 ' ...
        '94.44689941 94.46385193 94.46605682 94.4646759 94.46194458 94.45259094 94.45307159 94.43483734 94.44278717 94.44541168 94.43717957 94.44901276 94.43118286 94.44146729 94.43132019 94.42181396 94.43022919 94.42745209 94.4223175 94.41934204 94.42246246 94.42222595 94.41995239 94.41693878 94.4072876 94.41427612 94.40185547 94.39559937 94.41001129 94.41477966 94.40158081 94.39703369 94.40602112 94.39633179 94.39427948 94.37967682 94.38954926 94.38656616 94.3837738 94.39540863 94.38772583 94.37526703 94.36078644 94.37960052 94.36883545 94.36988068 94.36408234 94.36341095 94.35823059 94.36540222 94.35009003 94.35674286 94.36071014 94.36396027 94.36119843 94.34994507 94.36051178 94.34823608 94.34967804 94.35174561 94.34497833 94.34197998 94.34780121 94.32910156 94.3331604 94.33254242 94.32758331 94.32762146 94.33015442 94.32816315 ' ...
        '94.32314301 94.32646942 94.30739594 94.30788422 94.30844879 94.30348969 94.30142212 94.30807495 94.31570435 94.29753876 94.29647827 94.30131531 94.30045319 94.27844238 94.28447723 94.28427887 94.2943573 94.28701782 94.2858429 94.28295135 94.2826004 94.27066803 94.28083038 94.26305389 94.27874756 94.28703308 94.28923035 94.29154968 94.28417969 94.26900482 94.28678131 94.26993561 94.26932526 94.28009033 94.27509308 94.28755188 94.26235199 94.27296448 94.2713623 94.27301788 94.28114319 94.26656342 94.26580048 94.26586914 94.27596283 94.27781677 94.27157593 94.26078033 94.27474976 94.26330566 94.27429199 94.26935577 94.27571869 94.28192139 94.26202393 94.27205658 94.27384949 94.27105713 94.27536011 94.27483368 94.28981781 94.28129578 94.2800827 94.28159332 94.28271484 94.28225708 94.28014374 94.2835083 94.29086304 94.28601837 ' ...
        '94.29058075 94.2911911 94.2802887 94.28587341 94.29814148 94.29441071 94.30545807 94.30701447 94.30402374 94.30805206 94.33196259 94.34017181 94.34643555 94.34973907 94.32447052 94.31272888 94.29415894 94.29817963 94.32058716 94.31124115 94.32241058 94.32796478 94.33344269 94.33660889 94.31161499 94.3157959 94.33675385 94.37380219 94.3219986 94.31948853 94.31398773 94.32987213 94.33747864 94.35559082 94.35256958 94.32780457 94.3130722 94.31461334 94.33194733 94.32913208 94.3396759 94.33227539 94.33919525 94.33763123 94.34627533 94.33999634 94.33318329 94.33700562 94.34357452 94.34083557 94.33909607 94.33335876 94.34327698 94.32262421 94.32656097 94.33177948 94.34181213 94.34013367 94.34754181 94.33208466 94.22627258 94.32620239 94.33513641 94.31188965 94.32587433 94.34780884 94.33123779 94.33415985 94.33873749 94.32431793 ' ...
        '94.32086182 94.33662415 94.33976746 94.32261658 94.32204437 94.327034 94.31420135 94.31450653 94.31512451 94.31219482 94.3055191 94.30651855 94.31179047 94.30082703 94.29417419 94.28818512 94.29412842 94.27941132 94.29048157 94.29235077 94.28145599 94.27323151 94.28405762 94.28334808 94.27043915 94.27294922 94.27185822 94.27326202 94.25567627 94.26490021 94.26634979 94.24344635 94.25005341 94.25193787 94.25046539 94.25357056 94.24768066 94.26002502 94.2590332 94.26303864 94.26992798 94.26644897 94.25350952 94.26363373 94.28614044 94.30405426 94.29975128 94.31568146 94.32682037 94.32861328 94.33082581 94.35150909 94.37450409 94.38970184 94.41065216 94.4249115 94.44649506 94.44913483 94.46533203 94.48310089 94.51374817 94.53616333 94.55680084 94.58259583 94.61117554 94.61266327 94.64289856 94.65924072 94.69406891 94.72137451 ' ...
        '94.73158264 94.76820374 94.79938507 94.82000732 94.85496521 94.85583496 94.89033508 94.9209671 94.94120789 94.97606659 94.98644257 95.02378082 95.03764343 95.06777191 95.07543945 95.10444641 95.12483978 95.1473999 95.1654129 95.17871857 95.18452454 95.20663452 95.23387909 95.24649811 95.27329254 95.26934814 95.27918243 95.28443909 95.30764771 95.28855133 95.32099915 95.32357788 95.35501862 95.3742981 95.37838745 95.39839172 95.40676117 95.38139343 95.38652802 95.41379547 95.4116745 95.41742706 95.44044495 95.44033051 95.45785522 95.4568634 95.44247437 95.4496994 95.45789337 95.47173309 95.48888397 95.49507141 95.51216125 95.51638031 95.50868225 95.50572968 95.49797821 95.52153015 95.53505707 95.55809021 95.5688858 95.57026672 95.56206512 95.56613922 95.55256653 95.57782745 95.59337616 95.60531616 95.59784698 95.59809875 ' ...
        '95.59269714 95.59043121 95.59577179 95.60132599 95.6089325 95.62839508 95.63018036 95.6394043 95.63388824 95.66107941 95.64479065 95.63663483 95.64968872 95.65555573 95.65281677 95.65918732 95.6593399 95.65633392 95.67543793 95.71071625 95.6676178 95.67266083 95.68457031 95.69195557 95.73518372 95.71907806 95.69673157 95.70464325 95.70722961 95.72090149 95.73904419 95.72283173 95.72542572 95.72335815 95.72637177 95.73452759 95.75995636 95.75925446 95.75469208 95.75256348 95.74910736 95.75121307 95.76198578 95.77953339 95.77894592 95.784935 95.79085541 95.77912903 95.78582764 95.78353882 95.795784 95.80587769 95.79415131 95.79947662 95.79093933 95.79598236 95.79592133 95.82116699 95.81208801 95.81230164 95.81033325 95.80327606 95.79692078 95.80548096 95.83571625 95.83479309 95.84248352 95.84329987 95.84072113 95.82065582 ' ...
        '95.82103729 95.84464264 95.85787201 95.86500549 95.84959412 95.84733582 95.82902527 95.86649323 95.87585449 95.86984253 95.86708069 95.85478973 95.85632324 95.88269806 95.88341522 95.89621735 95.88327789 95.87229919 95.84642792 95.88283539 95.89668274 95.90700531 95.88718414 95.87569427 95.88059235 95.89000702 95.91363525 95.89997864 95.89129639 95.88864899 95.90033722 95.91466522 95.90550995 95.90682983 95.90898132 95.90625 95.90072632 95.89888763 95.91558075 95.94262695 95.92195892 95.91409302 95.88793182 95.88092804 95.94339752 95.95389557 95.94029999 95.91204834 95.92043304 95.92709351 95.87129211 95.95910645 95.96985626 95.9362793 95.93423462 95.94262695 95.94006348 95.91188049 95.96204376 95.95742035 95.94004059 95.95831299 95.94654083 95.92725372 95.94851685 95.98549652 95.96775818 95.9475174 95.95545959 95.9338913 ' ...
        '95.96079254 95.97826385 95.99031067 95.97479248 95.96103668 95.95362854 95.95700836 95.97724152 95.99023438 95.9907608 95.98041534 95.95869446 95.96214294 95.96694946 95.97229004 95.97795868 95.98223114 95.9857254 95.96974182 95.97716522 95.98137665 95.98787689 96.00054932 95.98004913 95.98626709 95.97270966 95.98220825 95.9916153 95.993927 95.99131775 95.9885025 95.98874664 95.97169495 95.9890976 96.00707245 96.01091003 96.00654602 96.0138855 95.99677277 96.00239563 95.99307251 95.99875641 96.00788116 96.0021286 96.01599121 96.03064728 96.01220703 96.02111053 96.00519562 96.00611115 96.02158356 96.02735901 96.02020264 96.02664185 96.0252533 96.0223999 96.02929688 96.0327301 96.03794098 96.03224182 96.03071594 96.04271698 96.03810883 96.04597473 96.04750824 96.04117584 96.04777527 96.06525421 96.06909943 96.05964661 ' ...
        '96.05177307 96.0463562 96.0582962 96.05931854 96.06700897 96.07193756 96.08016968 96.0735321 96.07186127 96.08234406 96.07761383 96.07797241 96.07548523 96.07898712 96.0916214 96.10009003 96.110466 96.09861755 96.09936523 96.10134888 96.10223389 96.09377289 96.10169983 96.10674286 96.11125946 96.11689758 96.11213684 96.1159668 96.10980225 96.1105957 96.11263275 96.12308502 96.11960602 96.11724854 96.14400482 96.12119293 96.12943268 96.12926483 96.11226654 96.12773132 96.12404633 96.12828827 96.13095856 96.13726807 96.12795258 96.14620209 96.13716888 96.14177704 96.12858582 96.14849854 96.14696503 96.1561203 96.1446228 96.14559937 96.15026855 96.15097046 96.15736389 96.15046692 96.16358185 96.15583801 96.17035675 96.16517639 96.16449738 96.16001129 96.17183685 96.16030121 96.17324066 96.1722641 96.18011475 96.17921448 ' ...
        '96.17086029 96.16620636 96.14994812 96.15374756 96.13208771 96.16889954 96.19297028 96.17458344 96.1902771 96.17805481 96.17188263 96.17573547 96.17215729 96.1869812 96.18362427 96.19501495 96.19849396 96.19656372 96.19392395 96.19252777 96.19733429 96.20834351 96.2094574 96.20589447 96.22132874 96.21377563 96.22317505 96.21513367 96.21546173 96.21057129 96.22627258 96.1962204 96.20613098 96.22216034 96.23262787 96.23056793 96.22215271 96.21196747 96.2279129 96.21987152 96.23109436 96.23202515 96.23743439 96.24205017 96.22803497 96.22758484 96.22502899 96.241539 96.24082947 96.26159668 96.24436188 96.24621582 96.25280762 96.24391174 96.24954224 96.25963593 96.2506485 96.26294708 96.25175476 96.24920654 96.26674652 96.26359558 96.26607513 96.26931763 96.25885773 96.26721191 96.25704956 96.26348114 96.26490021 96.27414703 ' ...
        '96.25941467 96.26465607 96.26184845 96.26818085 96.2728653 96.27131653 96.26152802 96.26023865 96.27014923 96.27239227 96.28561401 96.51424408 96.10520935 96.27213287 96.28744507 96.27125549 96.26270294 96.27206421 96.29280853 96.29517365 96.29961395 96.29517365 96.28502655 96.29206085 96.29775238 96.2806778 96.2904892 96.30176544 96.41812134 96.2837677 96.2618866 96.28637695 96.31116486 96.29934692 96.31729126 96.31202698 96.31694794 96.30102539 96.31873322 96.32888031 96.32227325 96.33847046 96.32752228 96.3249054 96.31911469 96.32173157 96.33518982 96.34356689 96.34525299 96.33841705 96.34269714 96.31995392 96.3298111 96.34951782 96.34831238 96.35771179 96.35784149 96.35371399 96.34783173 96.35954285 96.34098053 96.35682678 96.36885071 96.365242 96.3601532 96.37262726 96.37265778 96.37109375 96.35890198 96.36691284 ' ...
        '96.35384369 96.36995697 96.3423996 96.34268951 96.39465332 96.40442657 96.42429352 96.39888763 96.38441467 96.39336395 96.39168549 96.39195251 96.40807343 96.40477753 96.41008759 96.38253784 96.409729 96.39622498 96.3894577 96.41860962 96.40880585 96.41760254 96.40945435 96.41439056 96.41416931 96.41779327 96.42095184 96.41770172 96.4287262 96.43134308 96.42247009 96.42346191 96.42723083 96.44451141 96.43474579 96.44220734 96.44076538 96.44220734 96.44059753 96.44185638 96.44795227 96.44039917 96.45185089 96.44960785 96.45043182 96.45726776 96.44815826 96.45454407 96.45529175 96.45259094 96.45314026 96.45645142 96.46120453 96.46341705 96.47024536 96.46299744 96.46534729 96.46977234 96.42733002 96.82749939 96.4864502 96.47354126 96.47642517 96.44854736 96.47386169 96.48288727 96.48287964 96.48731995 96.48332214 96.48088837 ' ...
        '96.50348663 96.50978088 96.56335449 96.44019318 96.46215057 96.48073578 96.48143768 96.47665405 96.47734833 96.49694061 96.50016785 96.5087738 96.54933167 96.50457764 96.49753571 96.49668121 96.49150848 96.51109314 96.53149414 96.53237915 96.49549103 96.50171661 96.51833344 96.51926422 96.53260803 96.51887512 96.53007507 96.52692413 96.53119659 96.52741241 96.52222443 96.43692017 96.55001831 96.59792328 96.55626678 96.53386688 96.52852631 96.53748322 96.5267868 96.6160202 96.48763275 96.51289368 96.54769897 96.54814911 96.54607391 96.53443909 96.5705719 96.57691193 96.54261017 96.55136871 96.51893616 96.58798218 96.57079315 96.56429291 96.55030823 96.55860901 96.58385468 96.56817627 96.5635376 96.57046509 96.57517242 96.56499481 96.5803299 96.57791901 96.56253815 96.56964874 96.58575439 96.57538605 96.58286285 96.58822632 ' ...
        '96.5798111 96.51170349 96.57937622 96.66571808 96.59658051 96.56795502 96.52909851 96.58591461 96.66395569 96.59024811 96.55311584 96.57169342 96.58176422 96.62798309 96.57656097 96.6109314 96.61057281 96.63169098 96.57537079 96.61035156 96.62492371 96.63626099 96.58916473 96.60280609 96.61434174 96.63684845 96.61000061 96.60996246 96.60795593 96.62975311 96.61759949 96.64912415 96.62712097 96.61443329 96.54324341 96.64144897 96.64949799 96.60829163 96.60536194 96.60520172 96.58185577 96.64464569 96.63366699 96.62981415 96.62822723 96.65306091 96.6301651 96.62039948 96.65882874 96.64414978 96.63246155 96.67103577 96.64752197 96.62212372 96.64845276 96.64899445 96.61923981 96.67848206 96.68859863 96.65020752 96.66055298 96.62056732 96.72891998 96.66806793 96.65925598 96.67149353 96.69937134 96.66542816 96.66439056 96.65847778 ' ...
        '96.65752411 96.66481018 96.6756134 96.67086792 96.67228699 96.67340088 96.68083954 96.6879425 96.66022491 96.70114899 96.6628952 96.66553497 96.72661591 96.67636108 96.69277954 96.66091156 96.7456665 96.74441528 96.68983459 96.65585327 96.74389648 96.68132019 96.66361237 96.73091888 96.70554352 96.72962189 96.71257019 96.70684814 96.71804047 96.72319031 96.70962524 96.70836639 96.74145508 96.70961761 96.73331451 96.7375412 96.72441101 96.68035889 96.77863312 96.70194244 96.69155121 96.72899628 96.71022034 96.71372986 96.74501801 96.74272919 96.74209595 96.75019073 96.75102997 96.75038147 96.74701691 96.74474335 96.73841858 96.74736786 96.75030518 96.74594116 96.73899078 96.74922943 96.7540741 96.74710846 96.74944305 96.74684143 96.75953674 96.75449371 96.7529068 96.75584412 96.75498962 96.75416565 96.77263641 96.78010559 ' ...
        '96.76423645 96.77651978 96.77005005 96.77641296 96.77339172 96.77987671 96.76973724 96.76911926 96.78421783 96.77881622 96.77723694 96.7696991 96.7861557 96.78318024 96.78961945 96.78362274 96.7821579 96.79368591 96.79111481 96.79208374 96.80128479 96.80062103 96.80252838 96.79823303 96.80960846 96.80065155 96.80974579 96.79915619 96.81240082 96.81403351 96.8195343 96.81130219 96.81245422 96.7987442 96.80774689 96.81384277 96.81698608 96.81098938 96.83760834 96.8340683 96.83428955 96.8249588 96.81841278 96.83345795 96.83117676 96.83506775 96.83135986 96.82210541 96.83182526 96.83291626 96.82685089 96.84869385 96.8379364 96.83496094 96.84606171 96.84299469 96.8469696 96.85562897 96.84477234 96.84925079 96.85228729 96.84716797 96.84953308 96.85582733 96.86644745 96.8577652 96.86325836 96.87011719 96.8731842 96.87317657 ' ...
        '96.87210846 96.85765839 96.87807465 96.88887787 96.87368011 96.86878204 96.87661743 96.88850403 96.87123871 96.8785553 96.87861633 96.8848877 96.8855896 96.87594604 96.8709259 96.89910126 96.89028931 96.89060211 96.88601685 96.92150116 96.88899231 96.91159058 96.90449524 96.89172363 96.90583038 96.9140625 96.91026306 96.90223694 96.93442535 96.9252243 96.93133545 96.91933441 96.91809082 96.91357422 96.9258728 96.92514038 96.93559265 96.94337463 96.94158936 96.93619537 96.93817902 96.9382019 96.9460144 96.9526825 96.94689178 96.94855499 96.9447937 96.95798492 96.96228027 96.95735931 96.95511627 96.95744324 96.96350098 96.95165253 96.96658325 96.97280884 96.97489166 96.96848297 96.98466492 96.99945068 97.00908661 96.9923172 96.99990082 96.99803925 96.98557281 96.97865295 96.9642868 96.98151398 96.97908783 97.01088715 ' ...
        '97.01547241 96.99707031 97.0274353 97.0056839 97.03318787 97.02635193 97.04433441 97.00639343 97.02347565 97.0485611 97.02651215 97.00963593 97.04759216 97.03987122 97.03787231 97.00275421 97.0191803 97.05141449 97.06110382 97.0267868 97.05112457 97.04755402 97.04304504 97.0586853 97.04636383 97.03324127 97.05964661 97.0715332 97.04888153 97.05553436 97.07521057 97.04340363 97.0672226 97.07594299 97.10168457 97.07899475 97.07004547 97.07872772 97.06594086 97.07176208 97.0530014 97.06669617 97.09604645 97.04981232 97.07496643 97.06356049 97.10540009 97.08080292 97.10558319 97.10353851 97.08878326 97.09822083 97.11042786 97.11396027 97.08331299 97.11297607 97.09181976 97.10931396 97.12134552 97.11632538 97.12866211 97.15898132 97.11133575 97.12893677 97.0915451 97.17425537 97.1219635 97.12194061 97.15896606 97.14913177 ' ...
        '97.1411438 97.1103363 97.13349915 97.16989136 97.11362457 97.19020081 97.17663574 97.21923828 97.14667511 97.17634583 97.16708374 97.17220306 97.17318726 97.17614746 97.18710327 97.17606354 97.16327667 97.18659973 97.17525482 97.18610382 97.17201233 97.21730804 97.22837067 97.22253418 97.17115021 97.22267914 97.1630249 97.22663879 97.15087128 97.19755554 97.14299011 97.19515991 97.22031403 97.18356323 97.2358017 97.15875244 97.1804657 97.20935059 97.20376587 97.22603607 97.20874786 97.22160339 97.23854065 97.25196075 97.2769928 97.24523926 97.18566895 97.19078064 97.22882843 97.23958588 97.27354431 97.30708313 97.25280762 97.28852844 97.24007416 97.26345825 97.24727631 97.30189514 97.24942017 97.22551727 97.23016357 97.29346466 97.27054596 97.24297333 97.23125458 97.22177124 97.2179184 97.29795837 97.28575134 97.26040649 ' ...
        '97.30259705 97.32949066 97.29529572 97.27972412 97.28348541 97.23083496 97.36766815 97.27906799 97.31739044 97.29223633 97.36479187 97.28437805 97.25027466 97.30316925 97.4190979 97.41410828 97.27384186 97.35633087 97.39808655 97.25807953 97.39332581 97.24929047 97.45705414 97.30892944 97.32164001 97.3553009 97.34772491 97.34680176 97.4004364 97.37372589 97.36626434 97.29847717 97.36652374 97.36455536 97.41307831 97.34533691 97.38262177 97.28858185 97.25863647 97.38790894 97.38273621 97.32520294 97.4970932 97.3525238 97.5357132 97.41819 97.37031555 97.3387146 97.36560822 97.44879913 97.42256165 97.35163116 97.3848114 97.40378571 97.59620667 97.53367615 97.33963013 97.44738007 97.47901917 97.34651184 97.41384888 97.45697784 97.50007629 97.37635803 97.46937561 97.45288849 97.58644867 97.47372437 97.40711212 97.66042328 ' ...
        '97.48039246 97.46086884 97.56629944 97.52906799 97.44064331 97.46759796 97.27215576 97.32067108 97.47992706 97.39990234 97.39593506 97.66606903 97.51620483 97.51672363 97.38354492 97.57572937 97.47027588 97.35503387 97.48073578 97.60892487 97.53215027 97.4916153 97.41724396 97.49462891 97.49547577 97.41713715 97.53088379 97.541008 97.37687683 97.40007019 97.3951416 97.69469452 97.80170441 97.7020874 97.72902679 97.34848022 97.59797668 97.81045532 97.4431839 97.63844299 97.86388397 97.81891632 97.25875854 97.54963684 97.71889496 97.73287201 97.63585663 97.59327698 97.6738739 97.7507019 97.80434418 97.83113098 97.63152313 97.71569824 97.74623871 97.54859924 97.76357269 97.63397217 97.73873138 97.75902557 97.62569427 97.90908051 97.78120422 97.95845795 97.80017853 97.42810822 97.75613403 97.56738281 97.70307922 97.75291443 ' ...
        '97.71098328 97.60203552 97.89016724 97.6138382 97.52086639 97.90597534 97.78414154 97.80535126 97.83299255 97.59703064 97.70617676 97.58380127 97.61579895 97.5983429 97.92637634 97.66466522 97.70365906 97.80727386 97.63367462 97.69061279 97.63471985 97.75852966 97.63182068 97.84598541 97.68122101 97.85132599 97.79447174 97.62584686 97.67953491 97.58071899 97.59953308 97.63719177 97.644104 97.74067688 97.92693329 97.83557892 97.72585297 97.68822479 97.5076828 97.77993011 97.70788574 97.62612152 97.82844543 97.7191391 97.78527832 97.59213257 97.81877136 97.7072525 97.6388855 97.76364899 97.74520874 97.73680878 97.75043488 97.80532837 97.70183563 97.66027069 97.84054565 97.41926575 97.65550232 97.71394348 97.73443604 97.70246887 97.69510651 97.62346649 97.90505981 97.95454407 97.88659668 97.71482086 97.72852325 97.78871155 ' ...
        '97.80438995 97.75891113 97.82653046 97.74784088 97.76651001 97.81428528 97.88761139 97.68928528 97.66545868 97.65007782 97.67523193 97.78459167 97.75770569 97.74026489 97.83190918 97.76564789 97.89241791 97.63520813 97.78736115 97.71924591 97.82278442 97.88315582 97.82639313 97.76638794 97.79817963 97.84809113 97.93048859 97.78503418 97.66512299 97.86882019 97.84812164 97.98261261 97.78987885 98.02326202 97.73554993 97.74311829 97.75019073 97.85800934 97.79354858 97.89825439 97.78253937 97.83566284 97.81563568 97.74399567 97.73316193 97.8527298 97.86793518 97.75434875 97.86737823 97.7359314 97.78721619 97.83343506 97.90293884 97.94042969 97.81770325 97.73987579 97.81401062 97.71129608 97.8925705 97.78391266 97.76802063 97.85719299 97.95475006 97.8494873 97.77976227 97.81741333 97.8395462 97.91307068 97.82302856 97.84056854 ' ...
        '97.89910126 97.87282562 97.7048111 97.77204132 97.88874054 97.89144135 97.70631409 97.7953186 97.83854675 97.93862915 97.7900238 97.74423981 97.75708008 97.77925873 97.84602356 97.75288391 97.75325012 97.8531723 97.90753174 97.85035706 97.76729584 97.88228607 97.76166534 97.86194611 97.83612823 97.74282837 97.72490692 97.89887238 97.91280365 97.82556915 97.75073242 97.88936615 97.80500031 97.83525085 97.72268677 97.75774384 97.72533417 97.78366089 97.83395386 97.73438263 97.80874634 97.74664307 97.70939636 97.80673218 97.93333435 97.79785919 97.81987 97.86108398 97.73957062 97.89770508 97.8025589 97.83226013 97.75219727 97.85312653 97.85945129 97.76147461 97.83475494 97.81420898 97.78375244 97.85160828 97.72909546 97.78664398 97.79962921 97.86339569 97.78514862 97.86087799 97.83149719 97.77233124 97.80250549 97.80799103 ' ...
        '97.84964752 97.84128571 97.82302094 97.75445557 97.7462616 97.81913757 97.75958252 97.76200867 97.8250885 97.85242462 97.7804184 97.80641174 97.72470856 97.72748566 97.77117157 97.76122284 97.78864288 97.75746155 97.76670837 97.67446136 97.74358368 97.84332275 97.71881866 97.76665497 97.8163147 97.79418945 97.80187225 97.76663208 97.75483704 97.8380661 97.69533539 97.70217133 97.75457001 97.84705353 97.84765625 97.72035217 97.71876526 97.75672913 97.74150085 97.66264343 97.76229858 97.79804993 97.72234344 97.72097015 97.69776154 97.78465271 97.74919891 97.76985931 97.67033386 97.7556076 97.70413208 97.70607758 97.57297516 97.75463104 97.78018951 97.68575287 97.70729828 97.63176727 97.74541473 97.77452087 97.69356537 97.63240814 97.59949493 97.73865509 97.73495483 97.80381012 97.68135834 97.74447632 97.68476105 97.66163635 ' ...
        '97.67007446 97.62711334 97.64696503 97.68832397 97.62978363 97.81468201 97.69906616 97.66257477 97.69684601 97.68340302 97.61491394 97.68321991 97.65869141 97.61827087 97.62102509 97.60920715 97.65394592 97.641716 97.65383911 97.65013123 97.67891693 97.65958405 97.75143433 97.68418121 97.70239258 97.71359253 97.69508362 97.608078 97.70833588 97.7040329 97.60082245 97.60673523 97.68094635 97.67045593 97.59247589 97.67835236 97.58424377 97.65708923 97.60521698 97.62863159 97.65751648 97.55304718 97.743927 97.6075592 97.65380096 97.7073288 97.58521271 97.67493439 97.65995789 97.67788696 97.56908417 97.57833099 97.6161499 97.59306335 97.62068176 97.71426392 97.68073273 97.72589111 97.6813736 97.69680786 97.67250061 97.56868744 97.6081543 97.57317352 97.6475296 97.67173767 97.53577423 97.65735626 97.60852814 97.63659668 ' ...
        '97.65184021 97.68070984 97.64995575 97.67186737 97.61381531 97.59629822 97.71097565 97.68106079 97.64713287 97.58932495 97.63574219 97.66336823 97.64291382 97.64248657 97.72773743 97.73016357 97.67539215 97.64981079 97.63101959 97.63630676 97.66394806 97.63779449 97.6631546 97.71310425 97.63536835 97.68752289 97.62533569 97.64794159 97.63731384 97.6525116 97.61819458 97.67326355 97.67147827 97.66422272 97.60144043 97.67739105 97.7204361 97.75221252 97.60775757 97.70948029 97.71881866 97.7270813 97.64222717 97.6077652 97.69376373 97.70359802 97.61193085 97.71492767 97.69198608 97.62203979 97.66007233 97.71442413 97.64337158 97.72373199 97.59276581 97.66156006 97.75195313 97.66838837 97.63430023 97.57158661 97.75621796 97.70884705 97.72239685 97.60809326 97.71752167 97.65969086 97.65626526 97.69261169 97.70063782 97.67995453 ' ...
        '97.58587646 97.64443207 97.62026215 97.68239594 97.65137482 97.7186203 97.77941132 97.6408844 97.73295593 97.66863251 97.66149139 97.59165955 97.69424438 97.63072968 97.64452362 97.70329285 97.70587921 97.57077026 97.68939209 97.68315887 97.60189819 97.58089447 97.67098999 97.72186279 97.70539856 97.68904114 97.72834778 97.65322876 97.62837219 97.66887665 97.71381378 97.67489624 97.65370941 97.67474365 97.66397095 97.54892731 97.63589478 97.66887665 97.62870789 97.54825592 97.6484375 97.59514618 97.50119019 97.61867523 97.57594299 97.61947632 97.60160828 97.66678619 97.60593414 97.60140228 97.54863739 97.59780121 97.55987549 97.72497559 97.54220581 97.60681152 97.62521362 97.59968567 97.56360626 97.60231781 97.59099579 97.6474762 97.61727142 97.56182098 97.58498383 97.59558105 97.59615326 97.51164246 97.58164978 97.63948059 ' ...
        '97.56491089 97.56558228 97.5635376 97.58517456 97.57138824 97.62094879 97.6102829 97.54302979 97.53738403 97.55973053 97.65258789 97.63204193 97.62563324 97.55661011 97.5625 97.59885406 97.55532837 97.54389191 97.50232697 97.47275543 97.65653992 97.57302856 97.54619598 97.56814575 97.56876373 97.63021851 97.60150146 97.56066132 97.61296844 97.64640808 97.46174622 97.58245087 97.55554199 97.49234009 97.61680603 97.57756042 97.58207703 97.53452301 97.54903412 97.55602264 97.62607574 97.50223541 97.65393829 97.57929993 97.5895462 97.52323914 97.51467133 97.57910156 97.59046173 97.53055573 97.49343872 97.55817413 97.49874115 97.5218277 97.53996277 97.53342438 97.49069214 97.43171692 97.40634155 97.55563354 97.54447937 97.61103821 97.49021912 97.55258179 97.51384735 97.53469849 97.56334686 97.53263855 97.50936127 97.48828888 ' ...
        '97.4404068 97.50624847 97.51397705 97.5404892 97.54839325 97.35513306 97.50041199 97.48645782 97.51128387 97.54188538 97.39505005 97.47463226 97.48973846 97.37995148 97.42814636 97.48910522 97.49851227 97.45624542 97.47620392 97.40224457 97.38841248 97.35541534 97.5072403 97.42198181 97.43356323 97.42166138 97.37258911 97.45552063 97.44384766 97.42494965 97.44993591 97.33751678 97.27931213 97.47627258 97.39634705 97.40855408 97.39206696 97.41566467 97.29042816 97.31018829 97.41280365 97.2566452 97.39209747 97.40283966 97.38892365 97.43991852 97.41598511 97.37405396 97.42726135 97.38305664 97.3279953 97.45623016 97.45651245 97.33895874 97.25572205 97.37506104 97.39139557 97.35375977 97.28978729 97.41819763 97.3793869 97.39059448 97.45155334 97.31145477 97.28762054 97.25235748 97.36738586 97.33969879 97.4157486 97.26820374 ' ...
        '97.32106781 97.33329773 97.31752014 97.27220154 97.19235992 97.34147644 97.35317993 97.42024231 97.37389374 97.15003204 97.30484009 97.15517426 97.33295441 97.22060394 97.28401184 97.25090027 97.07648468 97.21199036 97.33200073 97.10917664 97.42263794 97.34742737 97.15049744 97.18740082 97.10918427 97.19760132 97.28887939 97.25482941 97.20779419 97.13446808 97.23503113 97.14989471 97.06620789 97.19366455 97.14252472 97.17648315 97.20226288 96.97719574 97.14416504 97.03019714 96.99830627 97.14041138 97.04915619 97.17103577 97.04086304 97.15172577 97.08583832 97.15400696 97.04925537 97.00346375 96.93697357 96.99490356 96.99349213 97.02811432 96.86172485 96.9031601 97.07070923 96.93255615 96.92823029 97.06632233 96.89071655 96.85945129 96.69155121 96.87332916 96.85596466 96.66332245 96.76255798 96.8966217 96.87631989 96.92390442 ' ...
        '96.75009918 96.85125732 96.66016388 96.83235931 96.63015747 96.56554413 96.57327271 96.68556976 96.71627808 96.52648926 96.55362701 96.70614624 96.61742401 96.59432983 96.603508 96.49372101 96.53947449 96.41933441 96.57254791 96.64661407 96.52648926 96.54242706 96.57392883 96.44812775 96.42382813 96.44561768 96.63523865 96.39385223 96.67899323 96.48358917 96.3342514 96.32987213 96.3367157 96.40637207 96.26285553 96.49318695 96.28721619 96.38552856 96.40899658 96.30643463 96.28623962 96.34992218 96.20438385 96.40791321 96.20574188 96.12751007 96.39962006 96.2151413 96.17478943 96.37609863 96.11722565 96.24487305 95.8144989 96.29795837 96.20126343 96.07843018 95.93474579 96.12922668 95.8818512 96.16362762 95.90167999 96.03997803 95.89469147 96.10629272 96.10654449 95.80031586 96.17342377 96.02161407 96.14139557 96.08828735 ' ...
        '95.77243042 95.65727997 95.83570099 95.94207764 95.85021973 95.87204742 95.83716583 95.6219101 95.82420349 95.75283051 95.77083588 95.69322968 95.87326813 95.76940918 95.86610413 95.92921448 95.79356384 95.75606537 95.79912567 95.55023193 95.49801636 95.67459106 95.32515717 95.30597687 95.55807495 95.4984436 95.65641785 95.26220703 95.22053528 95.38827515 95.4708252 95.57458496 95.39131165 95.06145477 95.31215668 95.2493515 95.45207214 95.21085358 94.85439301 95.2756958 95.33159637 95.04052734 94.88454437 94.94023895 94.95026398 95.12684631 95.07006836 95.08226013 95.32873535 94.80016327 94.86981201 95.22741699 95.37508392 95.12332153 94.98592377 94.85834503 95.08808136 95.22012329 94.86078644 94.94863129 94.85946655 95.15323639 95.17640686 94.79393768 94.83213806 94.79590607 94.5767746 94.99033356 94.80060577 94.95903778 ' ...
        '94.61777496 94.81806183 94.57402802 94.62646484 94.76125336 94.63114929 94.74298859 94.66802216 94.5102005 94.8649292 94.44153595 94.405159 94.44296265 94.29481506 94.78689575 94.19018555 94.34200287 94.55805969 94.11876678 94.03842926 ' ...
        ], '%f');
end

function est_createSGWindowButton(f,w)
    uicontrol(f,'Style','pushbutton','String',sprintf('SG window: %d',w), ...
        'Units','normalized','Position',[0.65 0.955 0.17 0.035], ...
        'FontSize',11,'Callback',@(~,~)est_requestSGWindow(f,w));
end
function est_requestSGWindow(f,w)
    answer = inputdlg({'SG second-derivative window (odd points on the 1 nm grid):'}, ...
        'Set SG window for current and following samples',[1 65],{num2str(w)});
    if isempty(answer) || ~isgraphics(f), return; end
    value = str2double(answer{1}); input = getappdata(f,'SGCurrentInput');
    if ~isfinite(value) || value~=fix(value) || mod(value,2)~=1 || value<=input{5}
        errordlg('Enter an odd integer greater than the polynomial order.'); return;
    end
    try
        if value > numel(input{1})-4, error('SG window exceeds the available spectrum length.'); end
        result = est_calculateSpectrumD2(input{1},input{2},input{3},input{4},value,input{5},input{6});
        if min(result.Wavelength)>input{6}(1) || max(result.Wavelength)<input{6}(2)
            error('Window too large to preserve the full display interval.');
        end
    catch ME, errordlg(ME.message); return; end
    if value==w, return; end
    answer = questdlg(['Use this window for the current and following samples? ', ...
        'Current unsaved points will be cleared. Earlier saved results retain their own settings; ', ...
        'use one window throughout a series when comparing amplitudes.'], ...
        'Apply SG window','Apply','Cancel','Cancel');
    if strcmp(answer,'Apply'),setappdata(f,'PendingSGWindow',value);drawnow;end
end
function est_recordSGSettings(file,sheet,sample,w,p,overwrite)
    header={'Mineral_sheet','Sample_ID','SG_D2_window_points','SG_polynomial_order','R_presmoothing','Grid_spacing_nm'};
    data=cell(0,6);
    if isfile(file)
        try
            data=readcell(file,'Sheet','SG_parameters');
            if ~isempty(data),data=data(2:end,:);end
        catch, data=cell(0,6);end
    end
    index=[];
    for k=1:size(data,1)
        if strcmp(char(string(data{k,1})),sheet) && strcmp(char(string(data{k,2})),char(string(sample)))
            index=k; break;
        end
    end
    if ~isempty(index) && ~overwrite,return;end
    row={sheet,char(string(sample)),w,p,'5 points/order 2',1};
    if isempty(index),data(end+1,:)=row;else,data(index,:)=row;end
    writecell([header;data],file,'Sheet','SG_parameters');
end

function est_createSGGuideButton(f)
    uicontrol(f,'Style','pushbutton','String','SG guide curves', ...
        'Units','normalized','Position',[0.46 0.955 0.17 0.035], ...
        'FontSize',11,'Callback',@(~,~)est_requestSGGuides(f));
end
function est_requestSGGuides(f)
    previous = getappdata(f,'SGGuideWindows');
    answer = inputdlg({sprintf(['Enter guide SG windows (odd integers greater than the polynomial order).\n', ...
        'Example: 39 59 99   or   39,59,99\n', ...
        'Enter numbers only, without brackets, quotation marks, or nm.\n', ...
        'Reopen to edit the list. Clear the input and confirm to remove all guides.\n', ...
        'Guides are visual only. Selections and amplitudes use the main curve.'])}, ...
        'SG guide curves - example: 39 59 99',[1 75],{strtrim(sprintf('%d ',previous))});
    if isempty(answer) || ~isgraphics(f),return;end
    % A multi-line inputdlg can return a padded character matrix.
    % Join its rows in reading order before splitting the window list.
    rawText = answer{1};
    if ischar(rawText)
        inputText = strjoin(cellstr(rawText), ' ');
    elseif isstring(rawText)
        inputText = strjoin(cellstr(rawText(:)), ' ');
    elseif iscell(rawText)
        inputText = strjoin(cellstr(string(rawText(:))), ' ');
    else
        errordlg('Enter window numbers, for example: 39 49 59 99.'); return;
    end
    inputText = strtrim(inputText);
    if isempty(inputText)
        values=[];
    else
        tokens=regexp(inputText,'[,;，；\s]+','split');
        values=str2double(tokens);input=getappdata(f,'SGCurrentInput');
        if any(~isfinite(values)|values~=fix(values)|mod(values,2)~=1|values<=input{5})
            errordlg('All windows must be odd integers greater than the polynomial order.');return;
        end
        values=unique(values,'stable');
        for w=values
            try
                if w > numel(input{1})-4, error('SG window exceeds the available spectrum length.'); end
                result=est_calculateSpectrumD2(input{1},input{2},input{3},input{4},w,input{5},input{6});
                if isempty(result.Wavelength) || min(result.Wavelength)>input{6}(1) || max(result.Wavelength)<input{6}(2)
                    error('Window too large to preserve the full display interval.');
                end
            catch ME,errordlg(sprintf('SG %d: %s',w,ME.message));return;end
        end
    end
    setappdata(f,'SGGuideWindows',values);
    est_drawSGGuides(f);drawnow;
end
function est_drawSGGuides(f)
    ax=getappdata(f,'SGGuideAxes');
    if isempty(ax)||~isgraphics(ax),return;end
    delete(findobj(ax,'Tag','SGGuideCurve'));
    legend(ax,'off');
    windows=getappdata(f,'SGGuideWindows');
    if isempty(windows),return;end
    input=getappdata(f,'SGCurrentInput');
    mainWindow=getappdata(f,'SGMainWindow');
    colors=lines(numel(windows));
    handles=findobj(ax,'Tag','SGMainCurve');
    labels={sprintf('Main SG %d (measurement)',mainWindow)};
    hold(ax,'on');
    for j=1:numel(windows)
        if windows(j)==mainWindow,continue;end
        try
            result=est_calculateSpectrumD2(input{1},input{2},input{3},input{4},windows(j),input{5},input{6});
            if isempty(result.Wavelength)||min(result.Wavelength)>input{6}(1)||max(result.Wavelength)<input{6}(2)
                warning('Guide SG %d omitted: insufficient wavelength coverage.',windows(j));continue;
            end
            h=plot(ax,result.Wavelength,result.D2,'--','Color',colors(j,:), ...
                'LineWidth',1.35,'Tag','SGGuideCurve','HitTest','off','PickableParts','none');
            handles(end+1)=h; %#ok<AGROW>
            labels{end+1}=sprintf('Guide SG %d',windows(j)); %#ok<AGROW>
        catch ME
            warning('Guide SG %d omitted: %s',windows(j),ME.message);
        end
    end
    if numel(handles)>1
        lg=legend(ax,handles,labels,'Location','northeast','Interpreter','none');
        lg.AutoUpdate='off';lg.FontSize=8;
    end
end

function tf = isLegacyResultFile(name)
    % Preserve exclusion of result workbooks written before the application rename.
    legacyPrefix = char([90 76 83]);
    tf = startsWith(name, strcat(legacyPrefix, ...
        {'_DIY_','_Advanced_','_Configurable_','_REL_'}), 'IgnoreCase', true);
end
