function [AUC,nze] = crossval_spls_da(x,y,lvs,keepXs,blocks_r,prepx,prepy,opt,coef)

% Row-wise k-fold (rkf) cross-validation in SPLS-DA. We correct the 
% classification limit following Richard G. Brereton, J. Chemometrics 2014; 
% 28: 213–225. We extend to several classes by counting positives/negatives
% in each response dummy variable indečndently.
%
% AAUC = crossval_spls_da(x,y) % minimum call
% [AAUC, AUC,nze] =
% crossval_spls_da(x,y,lvs,keepXs,blocks_r,prepx,prepy,opt) % complete call
%
%
% INPUTS:
%
% x: [NxM] billinear data set for model fitting
%
% y: [NxO] billinear data set of dummy variables (+1, -1)
%
% lvs: [1xA] Latent Variables considered (e.g. lvs = 1:2 selects the
%   first two LVs). By default, lvs = 0:rank(x)
%
% keepXs: [1xK] Numbers of x-block variables kept per latent variable modeled. 
%   By default, keepXs = 1:M
%
% blocks_r: [1x1] maximum number of blocks of samples (the minimum number
%   of observations of a class divided by 2 by default)
%
% prepx: [1x1] preprocesing of the x-block
%       0: no preprocessing
%       1: mean centering
%       2: autoscaling (default)  
%
% prepy: [1x1] preprocesing of the y-block
%       0: no preprocessing
%       1: mean centering
%       2: autoscaling (default)  
%
% opt: (str or num) options for data plotting.
%       0: no plots.
%       1: plot (default)
%
%
% OUTPUTS:
%
% AAUC: [AxK] Macro-average Area Under the Curve in ROC
%
% AUC: [AxKxO] Area Under the Curve in ROC per variable
%
% nze: [AxK] Non-zero elements in the regression coefficient matrix.
%
%
% EXAMPLE OF USE: Random data with structural relationship
%
% X = simuleMV(20,10,8);
% Y = 2*(0.1*randn(20,1) + X(:,1)>0)-1;
% lvs = 0:10;
% keepXs = 1:10;
% [AUC,nze] = crossval_spls_da(X,Y,lvs,keepXs,5);
%
%
% coded by: Jose Camacho (josecamacho@ugr.es)
% last modification: 4/Nov/20
%
% Copyright (C) 2020  University of Granada, Granada
% Copyright (C) 2020  Jose Camacho Paez
% 
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.


%% Arguments checking

% Set default values
routine=dbstack;
assert (nargin >= 2, 'Error in the number of arguments. Type ''help %s'' for more info.', routine(1).name);
N = size(x, 1);
M = size(x, 2);
O = size(y, 2);

if nargin < 3 || isempty(lvs), lvs = 0:rank(x); end;
A = length(lvs);
if nargin < 4 || isempty(keepXs), keepXs = 1:M; end;
J =  length(keepXs);

ind = (size(y,2)+1)*ones(size(y,1),1);
[r,c]=find(y==1);
[r1,r2]=sort(r);
ind(r1) = c(r2);
vals = unique(ind);
rep = sort(histc(ind,vals),'ascend');
N2 = rep(1); % minimum length of a class
if nargin < 5 || isempty(blocks_r), blocks_r = max(2,N2); end;

if nargin < 6 || isempty(prepx), prepx = 2; end;
if nargin < 7 || isempty(prepy), prepy = 2; end;
if nargin < 8 || isempty(opt), opt = 1; end;

% Convert column arrays to row arrays
if size(lvs,2) == 1, lvs = lvs'; end;
if size(keepXs,2) == 1, keepXs = keepXs'; end;

% Validate dimensions of input data
assert (isequal(size(y), [N O]), 'Dimension Error: 2nd argument must be N-by-O. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(lvs), [1 A]), 'Dimension Error: 3rd argument must be 1-by-A. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(keepXs), [1 J]), 'Dimension Error: 4th argument must be 1-by-J. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(blocks_r), [1 1]), 'Dimension Error: 5th argument must be 1-by-1. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(prepx), [1 1]), 'Dimension Error: 6th argument must be 1-by-1. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(prepy), [1 1]), 'Dimension Error: 7th argument must be 1-by-1. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(opt), [1 1]), 'Dimension Error: 8th argument must be 1-by-1. Type ''help %s'' for more info.', routine(1).name);

% Preprocessing
lvs = unique(lvs);
keepXs = unique(keepXs);

% Validate values of input data
assert (isempty(find(y~=1 & y~=-1)), 'Value Error: 2rd argument must not contain values different to 1 or -1. Type ''help %s'' for more info.', routine(1).name);
assert (isempty(find(lvs<0)), 'Value Error: 3rd argument must not contain negative values. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(fix(lvs), lvs), 'Value Error: 3rd argument must contain integers. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(fix(keepXs), keepXs), 'Value Error: 4th argument must contain integers. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(size(blocks_r), [1 1]), 'Dimension Error: 5th argument must be 1-by-1. Type ''help %s'' for more info.', routine(1).name);
assert (isequal(fix(blocks_r), blocks_r), 'Value Error: 5th argument must be an integer. Type ''help %s'' for more info.', routine(1).name);
assert (blocks_r>1, 'Value Error: 5th argument must be above 1. Type ''help %s'' for more info.', routine(1).name);
assert (blocks_r<=N2, 'Value Error: 5th argument must be at most %d. Type ''help %s'' for more info.', N2, routine(1).name);

%% Main code

% Initialization
AAUC = zeros(length(lvs),length(keepXs));
AUC = zeros(length(lvs),length(keepXs),O);
nze = zeros(length(lvs),length(keepXs));

ind = (size(y,2)+1)*ones(size(y,1),1);
[r,c]=find(y==1);
[r1,r2]=sort(r);
ind(r1) = c(r2);
vals = unique(ind);
for i=1:length(vals),
    y1{i} = find(ind==vals(i));
    rows = rand(1,length(y1{i}));
    [a,r_indn{i}]=sort(rows);
    elem_r(i)=length(y1{i})/blocks_r;
end

% Cross-validation
        
for i=1:blocks_r,
    
    cal = [];
    test = [];
    for j=1:length(vals)
        ind_in1 = r_indn{j}(round((i-1)*elem_r(j)+1):round(i*elem_r(j))); % Sample selection
        i2 = ones(length(y1{j}),1);
        i2(ind_in1)=0;
        cal = [cal;y1{j}(find(i2))];
        test = [test;y1{j}(ind_in1)];
    end
    sample = x(test,:);
    calibr = x(cal,:);
    sample_y = y(test,:);
    calibr_y = y(cal,:);  
    
    [ccs,av,st] = preprocess2D(calibr,prepx);    
    %[ccs_y,av_y,st_y] = preprocess2D(calibr_y,prepy);
    ccs_y = calibr_y;
    
    ind = (size(ccs_y,2)+1)*ones(size(ccs_y,1),1);
    [r,c]=find(ccs_y==1);
    [r1,r2]=sort(r);
    ind(r1) = c(r2);
    vals = unique(ind);    
    for j=1:length(vals)
        ind2 = find(ind==vals(j));
        if ~isempty(ind2),
            [kk,m(j,:)] = preprocess2D(ccs(ind2,:),1);  % additional subtraction of class mean
        end
    end
    ccs = preprocess2Dapp(ccs,mean(m));
        
    scs = preprocess2Dapp(sample,av,st);
    scs = preprocess2Dapp(scs,mean(m));

    %[ccs,PR] = reduce2(ccs,coef);
    
    if  ~isempty(find(lvs)),
        
        for lv=1:length(lvs),

            for keepX=1:length(keepXs),
                
                if lvs(lv),
                    model = sparsepls2(ccs, ccs_y, lvs(lv), keepXs(keepX)*ones(size(1:lvs(lv))), O*ones(size(1:lvs(lv))), 500, 1e-10, 1, 0);
                    beta = model.R*model.Q';
                   
                    srec1(test,lv,keepX,:) = scs*beta;%scs*PR*beta;
					nze(lv,keepX) = nze(lv,keepX) + length(find(beta)); 
                else
                    srec1(test,lv,keepX,:) = 0;
					nze(lv,keepX) = nze(lv,keepX) + M*O; 
                end
                
            end
            
        end
        
    else
        srec1(test,1,1,:) = 0;
		nze = nze + ones(length(keepXs),1)*M*O;
    end
    
end

for lv=1:size(srec1,2),
    for keepX=1:size(srec1,3),
        for o = 1:O,
            [~,~,~,AUC(lv,keepX,o)] = perfcurve(y(:,o),srec1(:,lv,keepX,o),1);
        end
    end
end

AAUC =  mean(AUC,3);


%% Show results

if opt == 1,
    fig_h = plot_vec(AAUC',keepXs,[],{'#NZV','AUC'},[],0,lvs); 
    legend('show')
end

