%clear all
close all
addpath('../libviso2/matlab/')
%% load data
img2Path = '../dataset/sequences/05/image_2/';
imgType = '*.png';
images2 = dir([img2Path imgType]);

%{
img3Path = '../dataset/sequences/05/image_3/';
images3 = dir([img3Path imgType]);
%}
K = [7.188560000000e+02 0.000000000000e+00 6.071928000000e+02;...
    0.000000000000e+00 7.188560000000e+02 1.852157000000e+02;...
    0.000000000000e+00 0.000000000000e+00 1.000000000000e+00];
R_w = [0 -1 0; 0 0 -1; 1 0 0]';

%{
K3 = [ 7.188560000000e+02 0.000000000000e+00 6.071928000000e+02;...
    0.000000000000e+00 7.188560000000e+02 1.852157000000e+02;...
    0.000000000000e+00 0.000000000000e+00 1.000000000000e+00];
H3 = [eye(3) [0 0.54 1.65]'];
%}
% matching parameters
param.nms_n                  = 2;   % non-max-suppression: min. distance between maxima (in pixels)
param.nms_tau                = 50;  % non-max-suppression: interest point peakiness threshold
param.match_binsize          = 50;  % matching bin width/height (affects efficiency only)
param.match_radius           = 200; % matching radius (du/dv in pixels)
param.match_disp_tolerance   = 1;   % du tolerance for stereo matches (in pixels)
param.outlier_disp_tolerance = 5;   % outlier removal: disparity tolerance (in pixels)
param.outlier_flow_tolerance = 5;   % outlier removal: flow tolerance (in pixels)
param.multi_stage            = 1;   % 0=disabled,1=multistage matching (denser and faster)
param.half_resolution        = 1;   % 0=disabled,1=match at half resolution, refine at full resolution
param.refinement             = 2;   % refinement (0=none,1=pixel,2=subpixel)

% init matcher
matcherMex('init',param);

%% run VSLAM

ground_bounds = [408 185 818 370]; % [xmin ymin xmax ymax]

%% get seed 3d points
% get matches between first two frames
im2_prev = imread([img2Path images2(1).name]);
im2_rgb = imread([img2Path images2(4).name]);
imsize = size(im2_rgb);
matcherMex('push',rgb2gray(im2_prev));
matcherMex('push',rgb2gray(im2_rgb));

matcherMex('match',0);
features = matcherMex('get_matches',0)';
matched_indices = matcherMex('get_indices',0)';

Mx = features(:,[1 3]);
My = features(:,[2 4]);

% get rid of outliers
V = 0;
while V < 0.35*prod(imsize(1:2))
    [~, ~, inliers] = GetInliersRANSAC([Mx(:,1) My(:,1)], [Mx(:,2),My(:,2)],0.005,10000);
    x1 = [Mx(inliers,1) My(inliers,1)];
    x2 = [Mx(inliers,2) My(inliers,2)];
    [~,V]=convhull(x1(:,1),x1(:,2));
end

% estimate pose (unscaled)
F = EstimateFundamentalMatrix(x1, x2);
E = EssentialMatrixFromFundamentalMatrix(F,K);

[Cset, Rset] = ExtractCameraPose(E);

% triangulate and resolve chirality
Xset = cell(4,1);
for i = 1 : 4
    Xset{i} = LinearTriangulation(K, zeros(3,1), eye(3), Cset{i}, Rset{i}, x1, x2);    
end
[C, R, X] = DisambiguateCameraPose(Cset, Rset, Xset);

X = NonlinearTriangulation(K, zeros(3,1), eye(3), C, R, x1, x2, X);

Cr_set{1} = zeros(3,1);
Rr_set{1} = eye(3,3);
Cr_set{2} = C;
Rr_set{2} = R;

%%
figure(1)
clf
mask = X(:,3) > 0 & sqrt(sum(X.^2,2)) < 3;
showPointCloud(X(mask,:)*R_w')
xlabel('x')
ylabel('y')
zlabel('z')

P1 = K*Rr_set{1}*[eye(3) -Cr_set{1}];
X_aug = [X ones(size(X,1),1)];
x1_p = bsxfun(@rdivide,P1(1:2,:)*X_aug',P1(3,:)*X_aug')';

P2 = K*Rr_set{2}*[eye(3) -Cr_set{2}];
x2_p = bsxfun(@rdivide,P2(1:2,:)*X_aug',P2(3,:)*X_aug')';

figure(2)
clf
imshow(im2_prev)
hold on
plot(x1_p(:,1),x1_p(:,2),'r*')
plot(x1(:,1),x1(:,2),'b*')

figure(3)
clf
imshow(im2_rgb)
hold on
plot(x2_p(:,1),x2_p(:,2),'r*')
plot(x2(:,1),x2(:,2),'b*')