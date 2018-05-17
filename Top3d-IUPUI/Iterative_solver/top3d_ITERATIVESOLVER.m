% AN 169 LINE 3D TOPOLOGY OPITMIZATION CODE BY LIU AND TOVAR (JUL 2013)
% ft = 1 for density filter, ft = 2 for sensitivity filter
% Designed for large scale problems
function [xPhys]=top3d_ITERATIVESOLVER(nelx,nely,nelz,volfrac,penal,rmin,ft)

% USER-DEFINED LOOP PARAMETERS
maxloop = 200;    % Maximum number of iterations
tolx = 0.01;      % Terminarion criterion
displayflag = 0;  % Display structure flag

% USER-DEFINED MATERIAL PROPERTIES
E0 = 1e8;           % Young's modulus of solid material
Emin = 1e-9;      % Young's modulus of void-like material
nu = 0.3;         % Poisson's ratio

% USER-DEFINED LOAD DOFs
il = nelx/2;
jl = nely;
kl = nelz/2;
loadnid = kl*(nelx+1)*(nely+1)+il*(nely+1)+(nely+1-jl); % Node IDs
loaddof = 3*loadnid(:) - 1;                             % DOFs

% USER-DEFINED SUPPORT FIXED DOFs
% Coordinates of the  fixed nodes
iif = [0 0 nelx nelx];
jf = [0 0 0 0];
kf = [0 nelz 0 nelz];

% Node IDs of fixed nodes
fixednid = kf*(nelx+1)*(nely+1)+iif*(nely+1)+(nely+1-jf); 

% location of the DOFs of the fixed nodes
fixeddof = [3*fixednid(:); 3*fixednid(:)-1; 3*fixednid(:)-2]; 


% PREPARE FINITE ELEMENT ANALYSIS
nele = nelx*nely*nelz; % total number of elements
ndof = 3*(nelx+1)*(nely+1)*(nelz+1); 
% total number of DOFs
F = sparse(ndof,1);
F(loaddof,1)=-1;
U = zeros(ndof,1);
freedofs = setdiff(1:ndof,fixeddof);
% unconstrained DOFs
KE = lk_H8(nu); % SIZE 24 * 24

% nodegrd contains the node ID of the first grid of nodes in the x-y plane
nodegrd = reshape(1:(nely+1)*(nelx+1),nely+1,nelx+1);
nodeids = reshape(nodegrd(1:end-1,1:end-1),nely*nelx,1);
nodeidz = 0:(nely+1)*(nelx+1):(nelz-1)*(nely+1)*(nelx+1);
nodeids = repmat(nodeids,size(nodeidz))+repmat(nodeidz,size(nodeids));

% edofVec contains the node IDs of the first node at each element
edofVec = 3*nodeids(:)+1; 

% edofMat: element connectivity matrix, size:nelx * 24, 
% containing the node IDs for each element
edofMat = repmat(edofVec,1,24)+ ...
    repmat([0 1 2 3*nely + [3 4 5 0 1 2] -3 -2 -1 ...
    3*(nely+1)*(nelx+1)+[0 1 2 3*nely + [3 4 5 0 1 2] -3 -2 -1]],nele,1);


% assemble the global stiffness matrix K
iK = reshape(kron(edofMat,ones(24,1))',24*24*nele,1); 
% SIZE 24nele * 24;the rows identifying the 24 * 24 * nele DOFs in the structure
jK = reshape(kron(edofMat,ones(1,24))',24*24*nele,1); 
% SIZE nele * 576;the columnsidentifying the 24 * 24 * nele DOFs in the structure

% PREPARE FILTER
iH = ones(nele*(2*(ceil(rmin)-1)+1)^2,1);
jH = ones(size(iH));
sH = zeros(size(iH));
k = 0;
for k1 = 1:nelz
    for i1 = 1:nelx
        for j1 = 1:nely
            e1 = (k1-1)*nelx*nely + (i1-1)*nely+j1;
            for k2 = max(k1-(ceil(rmin)-1),1):min(k1+(ceil(rmin)-1),nelz)
                for i2 = max(i1-(ceil(rmin)-1),1):min(i1+(ceil(rmin)-1),nelx)
                    for j2 = max(j1-(ceil(rmin)-1),1):min(j1+(ceil(rmin)-1),nely)
                        e2 = (k2-1)*nelx*nely + (i2-1)*nely+j2;
                        k = k+1;
                        iH(k) = e1;
                        jH(k) = e2;
                        sH(k) = max(0,rmin-sqrt((i1-i2)^2+(j1-j2)^2+(k1-k2)^2));
                    end
                end
            end
        end
    end
end
H = sparse(iH,jH,sH);
Hs = sum(H,2);
% INITIALIZE ITERATION
x = repmat(volfrac,[nely,nelx,nelz]);
xPhys = x;  % SIZE nelx * nely * nelz
loop = 0; 
change = 1;
% START ITERATION
while change > tolx && loop < maxloop
    loop = loop+1;
    % FE-ANALYSIS
    
    sK = reshape(KE(:)*(Emin+xPhys(:)'.^penal*(E0-Emin)),24*24*nele,1); 
    % SIZE 576 * nele; all elements stiffness matrices
    
    % Assemble the global stiffness matrix K
    K = sparse(iK,jK,sK); K = (K+K')/2;
    
    % Calculate the deformation
    % Preconditioned conjugate gradients method
    tolit = 1e-8;
    maxit = 8000;
    M = diag(diag(K(freedofs,freedofs)));
    U(freedofs,:) = pcg(K(freedofs,freedofs),F(freedofs,:),tolit,maxit,M);
    % tolit: tolerance
    % maxit: maximum number of iterations.
    % pcg(A,b,tol,maxit,M) and pcg(A,b,tol,maxit,M1,M2) use symmetric 
    % positive definite preconditioner M or M = M1*M2 and effectively solve
    % the system inv(M)*A*x = inv(M)*b for x. If M is [] then pcg applies 
    % no preconditioner. M can be a function handle mfun such that mfun(x) 
    % returns M\x.
    
    % Preconditioning is the application of a transformation, called the 
    % preconditioner, that conditions a given problem into a form that is 
    % more suitable for numerical solving methods. Preconditioning is typically 
    % related to reducing a condition number of the problem. 
    % The preconditioned problem is then usually solved by an iterative method.
    
    % Condition number:https://en.wikipedia.org/wiki/Condition_number
    % Condition number of a function with respect to an argument measures 
    % how much the output value of the function can change for a small change 
    % in the input argument.
    
    % OBJECTIVE FUNCTION AND SENSITIVITY ANALYSIS
    ce = reshape(sum((U(edofMat)*KE).*U(edofMat),2),[nely,nelx,nelz]);
    c = sum(sum(sum((Emin+xPhys.^penal*(E0-Emin)).*ce)));
    dc = -penal*(E0-Emin)*xPhys.^(penal-1).*ce;
    dv = ones(nely,nelx,nelz);
    % FILTERING AND MODIFICATION OF SENSITIVITIES
    if ft == 1
        dc(:) = H*(dc(:)./Hs);  
        dv(:) = H*(dv(:)./Hs);
    elseif ft == 2
        dc(:) = H * ( x(:).* dc(:) ) ./ Hs./ max(1e-3,x(:));
    end
    % OPTIMALITY CRITERIA UPDATE
    l1 = 0; l2 = 1e9; move = 0.2;
    while (l2-l1)/(l1+l2) > 1e-3
        lmid = 0.5*(l2+l1);
        xnew = max(0,max(x-move,min(1,min(x+move,x.*sqrt(-dc./dv/lmid)))));
        if ft == 1
        xPhys(:) = (H*xnew(:))./Hs;
        elseif ft == 2
            xPhys = xnew;
        end
        if sum(xPhys(:)) > volfrac*nele
            l1 = lmid; 
        else
            l2 = lmid; 
        end
    end
    change = max(abs(xnew(:)-x(:)));
    x = xnew;
    % PRINT RESULTS
    fprintf(' It.:%5i Obj.:%11.4f Vol.:%7.3f ch.:%7.3f\n',loop,c,mean(xPhys(:)),change);
    % PLOT DENSITIES
    if displayflag, clf; display_3D(xPhys); end %#ok<UNRCH>
end
clf; display_3D(xPhys);
end


% === GENERATE ELEMENT STIFFNESS MATRIX ===
function [KE] = lk_H8(nu)

% where does A come from? 
A = [32 6 -8 6 -6 4 3 -6 -10 3 -3 -3 -4 -8;
    -48 0 0 -24 24 0 0 0 12 -12 0 12 12 12];
% What is the relationship between A and k
k = 1/144*A'*[1; nu];

K1 = [k(1) k(2) k(2) k(3) k(5) k(5);
    k(2) k(1) k(2) k(4) k(6) k(7);
    k(2) k(2) k(1) k(4) k(7) k(6);
    k(3) k(4) k(4) k(1) k(8) k(8);
    k(5) k(6) k(7) k(8) k(1) k(2);
    k(5) k(7) k(6) k(8) k(2) k(1)];

K2 = [k(9)  k(8)  k(12) k(6)  k(4)  k(7);
    k(8)  k(9)  k(12) k(5)  k(3)  k(5);
    k(10) k(10) k(13) k(7)  k(4)  k(6);
    k(6)  k(5)  k(11) k(9)  k(2)  k(10);
    k(4)  k(3)  k(5)  k(2)  k(9)  k(12)
    k(11) k(4)  k(6)  k(12) k(10) k(13)];

K3 = [k(6)  k(7)  k(4)  k(9)  k(12) k(8);
    k(7)  k(6)  k(4)  k(10) k(13) k(10);
    k(5)  k(5)  k(3)  k(8)  k(12) k(9);
    k(9)  k(10) k(2)  k(6)  k(11) k(5);
    k(12) k(13) k(10) k(11) k(6)  k(4);
    k(2)  k(12) k(9)  k(4)  k(5)  k(3)];

K4 = [k(14) k(11) k(11) k(13) k(10) k(10);
    k(11) k(14) k(11) k(12) k(9)  k(8);
    k(11) k(11) k(14) k(12) k(8)  k(9);
    k(13) k(12) k(12) k(14) k(7)  k(7);
    k(10) k(9)  k(8)  k(7)  k(14) k(11);
    k(10) k(8)  k(9)  k(7)  k(11) k(14)];

K5 = [k(1) k(2)  k(8)  k(3) k(5)  k(4);
    k(2) k(1)  k(8)  k(4) k(6)  k(11);
    k(8) k(8)  k(1)  k(5) k(11) k(6);
    k(3) k(4)  k(5)  k(1) k(8)  k(2);
    k(5) k(6)  k(11) k(8) k(1)  k(8);
    k(4) k(11) k(6)  k(2) k(8)  k(1)];

K6 = [k(14) k(11) k(7)  k(13) k(10) k(12);
    k(11) k(14) k(7)  k(12) k(9)  k(2);
    k(7)  k(7)  k(14) k(10) k(2)  k(9);
    k(13) k(12) k(10) k(14) k(7)  k(11);
    k(10) k(9)  k(2)  k(7)  k(14) k(7);
    k(12) k(2)  k(9)  k(11) k(7)  k(14)];

% KE means 24*24 k0i matrix for an eight-node hexahedral element
KE = 1/((nu+1)*(1-2*nu))*...
    [ K1  K2  K3  K4;
    K2'  K5  K6  K3';
    K3' K6  K5' K2';
    K4  K3  K2  K1'];

end

% === DISPLAY 3D TOPOLOGY (ISO-VIEW) ===
function display_3D(rho)
[nely,nelx,nelz] = size(rho);
hx = 1; hy = 1; hz = 1;            % User-defined unit element size
face = [1 2 3 4; 2 6 7 3; 4 3 7 8; 1 5 8 4; 1 2 6 5; 5 6 7 8];
set(gcf,'Name','ISO display','NumberTitle','off');
for k = 1:nelz
    z = (k-1)*hz;
    for i = 1:nelx
        x = (i-1)*hx;
        for j = 1:nely
            y = nely*hy - (j-1)*hy;
            if (rho(j,i,k) > 0.5)  % User-defined display density threshold
                vert = [x y z; x y-hx z; x+hx y-hx z; x+hx y z; x y z+hx;x y-hx z+hx; x+hx y-hx z+hx;x+hx y z+hx];
                vert(:,[2 3]) = vert(:,[3 2]); vert(:,2,:) = -vert(:,2,:);
                patch('Faces',face,'Vertices',vert,'FaceColor',[0.2+0.8*(1-rho(j,i,k)),0.2+0.8*(1-rho(j,i,k)),0.2+0.8*(1-rho(j,i,k))]);
                hold on;
            end
        end
    end
end
axis equal; axis tight; axis off; box on; view([30,30]); pause(1e-6);
end
% =========================================================================
% === This code was written by K Liu and A Tovar, Dept. of Mechanical   ===
% === Engineering, Indiana University-Purdue University Indianapolis,   ===
% === Indiana, United States of America                                 ===
% === ----------------------------------------------------------------- ===
% === Please send your suggestions and comments to: kailiu@iupui.edu    ===
% === ----------------------------------------------------------------- ===
% === The code is intended for educational purposes, and the details    ===
% === and extensions can be found in the paper:                         ===
% === K. Liu and A. Tovar, "An efficient 3D topology optimization code  ===
% === written in Matlab", Struct Multidisc Optim, 50(6): 1175-1196, 2014, =
% === doi:10.1007/s00158-014-1107-x                                     ===
% === ----------------------------------------------------------------- ===
% === The code as well as an uncorrected version of the paper can be    ===
% === downloaded from the website: http://www.top3dapp.com/             ===
% === ----------------------------------------------------------------- ===
% === Disclaimer:                                                       ===
% === The authors reserves all rights for the program.                  ===
% === The code may be distributed and used for educational purposes.    ===
% === The authors do not guarantee that the code is free from errors, a