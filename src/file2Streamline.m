function m_sln=file2Streamline(sln,file_type)
switch file_type
    case 'SLN'
        assert(all(isfield(sln,{'GEOMETRY','GEOMINDX',...
            'ID_BEG','ID_END','ID_CELL',...
            'TIME_BEG','SWAT'})),'Input must be SLN!');
        sln.GEOMETRY.values=reshape(sln.GEOMETRY.values,3,[])';
        TIME_BEG=sln.TIME_BEG.values;
        zero_point=find(TIME_BEG==0);
        n_l=length(zero_point);
        if all(isfield(sln,{'FLORES','FLRWAT','FLROIL'}))
            m_sln=struct('BEGIN',cell(n_l,1),'END',cell(n_l,1),'GEOMETRY',cell(n_l,1),...
                'IFRACRES',cell(n_l,1),'PFRACRES',cell(n_l,1),'PFRACOIL',cell(n_l,1),'PFRACWAT',cell(n_l,1),...
                'SO',cell(n_l,1),'SW',cell(n_l,1),...
                'FR',cell(n_l,1),'FW',cell(n_l,1),'FO',cell(n_l,1),...
                'CELL',cell(n_l,1),...
                'MEANX',cell(n_l,1),'MEANY',cell(n_l,1),'MEANZ',cell(n_l,1),...
                'MEANSO',cell(n_l,1),'MEANSW',cell(n_l,1),...
                'MEANSODSW',cell(n_l,1),'TOF',cell(n_l,1),'TotalTOF',cell(n_l,1),...
                'MINX',cell(n_l,1),'MINY',cell(n_l,1),'MINZ',cell(n_l,1));
            minus_ind=0;
            for i=1:length(zero_point)
                i_a=zero_point(i)-minus_ind;
                i_a_geo=zero_point(i);
                minus_ind=minus_ind+1;
                if i~=length(zero_point)
                    i_b=zero_point(i+1)-minus_ind-1;
                    i_b_geo=zero_point(i+1)-1;
                else
                    i_b=length(TIME_BEG)-minus_ind;
                    i_b_geo=length(TIME_BEG);
                end
                m_sln(i).BEGIN=sln.ID_BEG.values(i);
                m_sln(i).END=sln.ID_END.values(i);
                m_sln(i).IFRACRES=sln.IFRACRES.values(i);
                m_sln(i).PFRACRES=sln.PFRACRES.values(i);
                m_sln(i).PFRACOIL=sln.PFRACOIL.values(i);
                m_sln(i).PFRACWAT=sln.PFRACWAT.values(i);
                
                m_sln(i).SW=sln.SWAT.values(i_a:i_b);
                m_sln(i).SO=1-m_sln(i).SW;
                m_sln(i).FR=sln.FLORES.values(i_a:i_b);
                m_sln(i).FW=sln.FLRWAT.values(i_a:i_b);
                m_sln(i).FO=sln.FLROIL.values(i_a:i_b);
                m_sln(i).CELL=sln.ID_CELL.values(i_a:i_b);
                m_sln(i).GEOMETRY=sln.GEOMETRY.values(i_a_geo:i_b_geo,:);
                m_sln(i).TOF=sln.TIME_BEG.values(i_a_geo:i_b_geo,:);
                m_sln(i).MEANX=mean(m_sln(i).GEOMETRY(:,1));
                m_sln(i).MEANY=mean(m_sln(i).GEOMETRY(:,2));
                m_sln(i).MEANZ=mean(m_sln(i).GEOMETRY(:,3));
                m_sln(i).MEANSO=mean(m_sln(i).SO);
                m_sln(i).MEANSW=mean(m_sln(i).SW);
                m_sln(i).MEANSODSW=sum(m_sln(i).SO)/sum(m_sln(i).SW);
                m_sln(i).TotalTOF=max(m_sln(i).TOF);
                m_sln(i).MINX=min(m_sln(i).GEOMETRY(:,1));
                m_sln(i).MINY=min(m_sln(i).GEOMETRY(:,2));
                m_sln(i).MINZ=min(m_sln(i).GEOMETRY(:,3));
%                 if isfield(sln,'SGAS')
%                     m_sln.SG = cell(n_l,1);
%                 end
            end
        else
            m_sln=struct('BEGIN',cell(n_l,1),'END',cell(n_l,1),'GEOMETRY',cell(n_l,1),...
                'SO',cell(n_l,1),'SW',cell(n_l,1),'CELL',cell(n_l,1),...
                'MEANX',cell(n_l,1),'MEANY',cell(n_l,1),'MEANZ',cell(n_l,1),...
                'MEANSO',cell(n_l,1),'MEANSW',cell(n_l,1),...
                'MEANSODSW',cell(n_l,1),'TOF',cell(n_l,1),'TotalTOF',cell(n_l,1),...
                'MINX',cell(n_l,1),'MINY',cell(n_l,1),'MINZ',cell(n_l,1));
            minus_ind=0;
            for i=1:length(zero_point)
                i_a=zero_point(i)-minus_ind;
                i_a_geo=zero_point(i);
                minus_ind=minus_ind+1;
                if i~=length(zero_point)
                    i_b=zero_point(i+1)-minus_ind-1;
                    i_b_geo=zero_point(i+1)-1;
                else
                    i_b=length(TIME_BEG)-minus_ind;
                    i_b_geo=length(TIME_BEG);
                end
                m_sln(i).BEGIN=sln.ID_BEG.values(i);
                m_sln(i).END=sln.ID_END.values(i);
                m_sln(i).SW=sln.SWAT.values(i_a:i_b);
                m_sln(i).SO=1-m_sln(i).SW;
                m_sln(i).CELL=sln.ID_CELL.values(i_a:i_b);
                m_sln(i).GEOMETRY=sln.GEOMETRY.values(i_a_geo:i_b_geo,:);
                m_sln(i).TOF=sln.TIME_BEG.values(i_a_geo:i_b_geo,:);
                m_sln(i).MEANX=mean(m_sln(i).GEOMETRY(:,1));
                m_sln(i).MEANY=mean(m_sln(i).GEOMETRY(:,2));
                m_sln(i).MEANZ=mean(m_sln(i).GEOMETRY(:,3));
                m_sln(i).MEANSO=mean(m_sln(i).SO);
                m_sln(i).MEANSW=mean(m_sln(i).SW);
                m_sln(i).MEANSODSW=sum(m_sln(i).SO)/sum(m_sln(i).SW);
                m_sln(i).TotalTOF=max(m_sln(i).TOF);
                m_sln(i).MINX=min(m_sln(i).GEOMETRY(:,1));
                m_sln(i).MINY=min(m_sln(i).GEOMETRY(:,2));
                m_sln(i).MINZ=min(m_sln(i).GEOMETRY(:,3));
                if isfield(sln,'SGAS')
                    m_sln.SG = cell(n_l,1);
                end
            end
        end
        
    case 'json'
        assert(all(isfield(sln,{'properties','name',...
            'position'})),'Input is illegal!');
        n_l=length(sln.position);
        sln.properties=json_properties_fix(sln.properties);
        
        m_sln=struct('GEOMETRY',cell(n_l,1),...
            'SO',cell(n_l,1),'SG',cell(n_l,1),'SW',cell(n_l,1),...
            'MEANX',cell(n_l,1),'MEANY',cell(n_l,1),'MEANZ',cell(n_l,1),...
            'MEANSO',cell(n_l,1),'MEANSW',cell(n_l,1),'MEANSG',cell(n_l,1),...
            'MEANSODSW',cell(n_l,1),'TOF',cell(n_l,1),'TotalTOF',cell(n_l,1),...
            'MINX',cell(n_l,1),'MINY',cell(n_l,1),'MINZ',cell(n_l,1));
        for i=1:n_l
            m_sln(i).GEOMETRY=sln.position{i};
            m_sln(i).SO=sln.properties(i).Oil_saturation;
            m_sln(i).SW=sln.properties(i).Water_saturation;
            m_sln(i).SG=1-m_sln(i).SW-m_sln(i).SO;
            m_sln(i).TOF=sln.properties(i).Time_of_flight_start;
            m_sln(i).MEANX=mean(m_sln(i).GEOMETRY(:,1));
            m_sln(i).MEANY=mean(m_sln(i).GEOMETRY(:,2));
            m_sln(i).MEANZ=mean(m_sln(i).GEOMETRY(:,3));
            m_sln(i).MEANSO=mean(m_sln(i).SO);
            m_sln(i).MEANSW=mean(m_sln(i).SW);
            m_sln(i).MEANSG=mean(m_sln(i).SG);
            m_sln(i).MEANSODSW=sum(m_sln(i).SO)/sum(m_sln(i).SW);
            m_sln(i).TotalTOF=max(m_sln(i).TOF);
            m_sln(i).MINX=min(m_sln(i).GEOMETRY(:,1));
            m_sln(i).MINY=min(m_sln(i).GEOMETRY(:,2));
            m_sln(i).MINZ=min(m_sln(i).GEOMETRY(:,3));
        end
        
    otherwise
        errordlg('¹Ø¼ü´Ê´íÎó','´íÎó');
 
end
function p=json_properties_fix(properties)
[n_l,n]=size(properties);
p=struct();
for j=1:n
    name=properties(1,j).name;
    name=replace(name,' ','_');
    name=replace(name,'(','');
    name=replace(name,')','');
    for i=1:n_l
        eval(sprintf('p(i).%s=properties(i,j).value;',name));
    end
end

