clear all
addpath('imu')
addpath('cam')
addpath('ref')
addpath('vicon')

%% declare dataset
dataset = 9;
imu_file = ['imuRaw' num2str(dataset)];
cam_file = ['cam' num2str(dataset)];
vicon_file = ['viconRot' num2str(dataset)];

%% load dataset
load('imu_params.mat')
imu = load(imu_file);
vicon = load(vicon_file);

%% plots
lims = [-1.1 1.1];

p_v = figure(1);
clf
r_vicon = eye(3);
p_vicon.x = plot3([0 r_vicon(1,1)],[0 r_vicon(2,1)],[0 r_vicon(3,1)],'r-*');
hold on
axis equal
grid on
title('Vicon Attitude')
xlabel('x')
ylabel('y')
zlabel('z')
xlim(lims);
ylim(lims);
zlim(lims);
p_vicon.y = plot3([0 r_vicon(1,2)],[0 r_vicon(2,2)],[0 r_vicon(3,2)],'g-*');
p_vicon.z = plot3([0 r_vicon(1,3)],[0 r_vicon(2,3)],[0 r_vicon(3,3)],'b-*');

p_g = figure(2);
clf
r_gyro = eye(3);
p_gyro.x = plot3([0 r_gyro(1,1)],[0 r_gyro(2,1)],[0 r_gyro(3,1)],'r-*');
hold on
axis equal
grid on
title('EKF Attitude')
xlabel('x')
ylabel('y')
zlabel('z')
xlim(lims);
ylim(lims);
zlim(lims);
p_gyro.y = plot3([0 r_gyro(1,2)],[0 r_gyro(2,2)],[0 r_gyro(3,2)],'g-*');
p_gyro.z = plot3([0 r_gyro(1,3)],[0 r_gyro(2,3)],[0 r_gyro(3,3)],'b-*');

p_a = figure(3);
clf
r_acc = eye(3);
p_acc.x = plot3([0 r_acc(1,1)],[0 r_acc(2,1)],[0 r_acc(3,1)],'r-*');
hold on
axis equal
grid on
title('Accelerometer Attitude')
xlabel('x')
ylabel('y')
zlabel('z')
xlim(lims);
ylim(lims);
zlim(lims);
p_acc.y = plot3([0 r_acc(1,2)],[0 r_acc(2,2)],[0 r_acc(3,2)],'g-*');
p_acc.z = plot3([0 r_acc(1,3)],[0 r_acc(2,3)],[0 r_acc(3,3)],'b-*');

%% initialize
Q = [0.01 0.01 0.01 0.01 0.01 0.01 0.01]'; % dynamics noise
R = 0.3*ones(4,1);%[0.2 0.2 0.2 0.2]'; % accelerometer noise
w_b = [params.roll_bias;params.pitch_bias;params.yaw_bias];
a_b = [params.ax_bias; params.ay_bias; params.az_bias];
a_tol = 1;
cutoff_high = 0.001;
RC_high = 1/(cutoff_high*2*pi);

q_0 = [1 0 0 0]';
w_0 = (imu.vals([5 6 4],1) - w_b)*params.sf_w;
mu_0 = [q_0; w_0];
S_0 = eye(length(mu_0));
vicon_idx = 1;
tic
start = toc;
prev = zeros(7,1);
w = zeros(3,1);
psi = 0;
for i = 2:length(imu.ts)
    % get dt and high-passed angular velocity vector
    dt = imu.ts(i)-imu.ts(i-1);
    alpha_hp = RC_high/(dt+RC_high);
    w_1 = (imu.vals([5 6 4],i)-w_b)*params.sf_w;
    w_0 = (imu.vals([5 6 4],i-1)-w_b)*params.sf_w;
    w = w*alpha_hp + alpha_hp*(w_1-w_0);
    %w = w_1;

    psi = psi+dt*w(3);
    
    % propagate first order integration
    A = [1/2*quat_mat([0;w])*dt zeros(4,3);...
        zeros(3,7)];
    mu = A*mu_0 + [mu_0(1:4); w];
    S = A*S_0*A'+diag(Q);
    
    % normalize propagated quaternion
    mu(1:4) = mu(1:4)/norm(mu(1:4));
    
    % update with accelerometer data if magnitude is reasonable
    a = (imu.vals(1:3,i)-a_b)*params.sf_a.*[-1;-1;1];
    if norm(a) < 9.81+a_tol && norm(a) > 9.81-a_tol ...
            && abs(a(1)) < 9.81-a_tol ...
            && abs(a(2)) < 9.81-a_tol
        roll = (atan2(a(2), a(3)));
        pitch = (atan2(-a(1), a(3)));
        q_v = rot_to_quat(vicon.rots(:,:,vicon_idx));
        %[~,~,yaw] = quat_to_euler(q_v);
        yaw = psi;
        if roll < -pi
            roll = roll + pi;
        elseif roll >= pi
            roll = roll - pi;
        end
        if pitch < -pi
            pitch = pitch + pi;
        elseif pitch >= pi
            pitch = pitch - pi;
        end
        q_a = euler_to_quat(roll,pitch,yaw);
        
        % create observation
        B = [eye(4) zeros(4,3)];
        O = B*[q_a;w];
        
        % calculate Kalman gain and covariance
        S_inv = inv(S)+B'/diag(R)*B;
        K = S_inv\B'/(diag(R)+B/S_inv*B');
        S = inv(S_inv);
        
        % update new mu
        mu = mu+K*(O-B*mu);
        
        %% plot the accelerometer angle
        rot2 = quat_to_rot(q_a);
            
        r_acc = rot2*eye(3);
        set(p_acc.x,'xdata',[0 r_acc(1,1)],'ydata',[0 r_acc(2,1)],'zdata',[0 r_acc(3,1)]);
        set(p_acc.y,'xdata',[0 r_acc(1,2)],'ydata',[0 r_acc(2,2)],'zdata',[0 r_acc(3,2)]);
        set(p_acc.z,'xdata',[0 r_acc(1,3)],'ydata',[0 r_acc(2,3)],'zdata',[0 r_acc(3,3)]);
        set(p_a,'Name',num2str(imu.ts(i)-imu.ts(1)));
        drawnow
    end
    
    % assign mu and sigma for next time step
    mu_0 = mu;
    S_0 = S;
    
    %% plotting
    % plot propagated rotation
    rot1 = quat_to_rot(mu(1:4));
    r_gyro = rot1*eye(3);
    
    set(p_gyro.x,'xdata',[0 r_gyro(1,1)],'ydata',[0 r_gyro(2,1)],'zdata',[0 r_gyro(3,1)]);
    set(p_gyro.y,'xdata',[0 r_gyro(1,2)],'ydata',[0 r_gyro(2,2)],'zdata',[0 r_gyro(3,2)]);
    set(p_gyro.z,'xdata',[0 r_gyro(1,3)],'ydata',[0 r_gyro(2,3)],'zdata',[0 r_gyro(3,3)]);
    set(p_g,'Name',num2str(imu.ts(i)-imu.ts(1)));
    drawnow
    
    lt = vicon.ts-vicon.ts(1) < imu.ts(i)-imu.ts(1);
    t_stamp = vicon.ts(lt);
    r_vicon = vicon.rots(:,:,length(t_stamp))*eye(3);
    set(p_vicon.x,'xdata',[0 r_vicon(1,1)],'ydata',[0 r_vicon(2,1)],'zdata',[0 r_vicon(3,1)]);
    set(p_vicon.y,'xdata',[0 r_vicon(1,2)],'ydata',[0 r_vicon(2,2)],'zdata',[0 r_vicon(3,2)]);
    set(p_vicon.z,'xdata',[0 r_vicon(1,3)],'ydata',[0 r_vicon(2,3)],'zdata',[0 r_vicon(3,3)]);
    set(p_v,'Name',num2str(vicon.ts(length(t_stamp))-vicon.ts(1)));
    drawnow
    %{
    if vicon.ts(vicon_idx)-vicon.ts(1) < imu.ts(i)-imu.ts(1)
        if vicon_idx+1 <= length(vicon.ts)
            vicon_idx = vicon_idx+1;
            r_vicon = vicon.rots(:,:,vicon_idx)*eye(3);
            set(p_vicon.x,'xdata',[0 r_vicon(1,1)],'ydata',[0 r_vicon(2,1)],'zdata',[0 r_vicon(3,1)]);
            set(p_vicon.y,'xdata',[0 r_vicon(1,2)],'ydata',[0 r_vicon(2,2)],'zdata',[0 r_vicon(3,2)]);
            set(p_vicon.z,'xdata',[0 r_vicon(1,3)],'ydata',[0 r_vicon(2,3)],'zdata',[0 r_vicon(3,3)]);
            set(p_v,'Name',num2str(vicon.ts(vicon_idx)-vicon.ts(1)));
            drawnow
        end
    end
    %}
    stop = toc;
    %fprintf('time: %6.6f\n', imu.ts(i)-imu.ts(1))
    pause(dt-(stop-start))
    start = stop;
end
