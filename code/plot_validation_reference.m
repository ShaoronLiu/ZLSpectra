function plot_validation_reference
% Plot included author-selected reference outputs; does not reprocess spectra.
root = fileparts(fileparts(mfilename('fullpath')));
c = readtable(fullfile(root,'data','calcium_carbonate','reference_outputs', ...
    'Calcium_carbonate-1117.xlsx'),'Sheet','Calcium_carbonate');
h = readtable(fullfile(root,'data','hematite','reference_outputs', ...
    'Hematite_5+29_zls.xlsx'),'Sheet','Hematite');
cx = c{:,1}; cy = c{:,4}; hx = h{:,1} * 100; hy = h{:,4};
figure('Name','ZLSpectra validation reference outputs','Color','w');
subplot(1,3,1); drawfit(cx,cy,false); title('Calcium carbonate'); ylabel('I_{Cc}');
subplot(1,3,2); k=hx<=10; drawfit(hx(k),hy(k),false); title('Hematite: 0-10%'); ylabel('I_{Hm}');
subplot(1,3,3); k=hx>=10; drawfit(hx(k),hy(k),true); title('Hematite: 10-100%'); ylabel('I_{Hm}');
end
function drawfit(x,y,useLog)
valid=isfinite(x)&isfinite(y); x=x(valid); y=y(valid);
if useLog, valid=x>0; x=x(valid); y=y(valid); end
scatter(x,y,30,'filled'); hold on;
xx=linspace(min(x),max(x),150);
if useLog, b=polyfit(log(x),y,1); yy=polyval(b,log(xx));
else, b=polyfit(x,y,1); yy=polyval(b,xx); end
plot(xx,yy,'k--'); xlabel('Mineral content (%)'); box on;
end
