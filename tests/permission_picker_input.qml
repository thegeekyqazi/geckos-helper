// Synthetic Qt mouse-input regression; requires a staged qs.gecko module with a disabled socket.
import QtQuick
import Quickshell
import Quickshell.Io
import QtTest
import qs.gecko
ShellRoot {
    id: root
    property int stage:0
    property int index:0
    property var cases:[['chat',705,1.5],['settings',705,1.5],['chat',360,2],['settings',360,2]]
    property var checks:[]
    property var picker:null
    function check(name,ok){checks.push({page:cases[index][0],width:cases[index][1],zoom:cases[index][2],name:name,passed:ok});}
    function find(item,name){if(item.objectName===name)return item;for(const c of item.children??[]){const r=find(c,name);if(r)return r;}return null;}
    FileView {id:report;path:'/tmp/gecko-ui-qa/permission-click-matrix.json'}
    FloatingWindow { implicitWidth:760;implicitHeight:960;visible:true
        Rectangle {id:page;width:705;height:960;color:Theme.bg
            Loader {id:loader;anchors.fill:parent}
        }
        TestCase {id:input;name:'PermissionClickMatrix';when:false}
    }
    Component{id:chat;ChatPage{}}
    Component{id:settings;SettingsPage{}}
    Timer {interval:200;running:true;repeat:true;onTriggered:{
        const c=root.cases[root.index];
        switch(root.stage++){
        case 0:
            Gecko.chatId='';Gecko.chatPermissionMode='';Gecko.defaultPermissionMode='default';Gecko.busy=false;
            page.width=c[1];Theme.setZoom(c[2]);loader.sourceComponent=c[0]==='chat'?chat:settings;
            break;
        case 1:
            root.picker=root.find(loader.item,c[0]==='chat'?'chatPermissionPicker':'defaultPermissionPicker');
            root.check('enabled',root.picker.enabled);
            input.mouseClick(root.picker,root.picker.width/2,root.picker.height/2);
            break;
        case 2:
            root.check('mouse opens menu',root.picker.popup.visible && root.picker.popup.height>100);
            root.check('menu height bounded',root.picker.popup.height<=260);
            root.check('six choices',root.picker.count===6);
            root.picker.popup.contentItem.grabToImage(r=>r.saveToFile(`/tmp/gecko-ui-qa/permission-menu-open-${root.index}.png`));
            root.picker.popup.contentItem.positionViewAtIndex(5,ListView.Contain);
            break;
        case 3:
            const row=root.picker.popup.contentItem.itemAtIndex(5);
            root.check('last choice reachable',!!row);
            if(row)input.mouseClick(row,row.width/2,row.height/2);
            break;
        case 4:
            root.check('selection closes menu',!root.picker.popup.visible);
            if(c[0]==='chat')root.check('click selects Full access',Gecko.chatPermissionMode==='bypassPermissions' && root.picker.currentValue==='bypassPermissions');
            else {
                root.check('offline default change rejected',Gecko.defaultPermissionMode==='default' && !Gecko.changingPermissions);
                root.check('display matches saved mode after rejection',root.picker.currentValue==='default');
            }
            page.grabToImage(r=>r.saveToFile(`/tmp/gecko-ui-qa/permission-click-${root.index}.png`));
            break;
        case 5:
            root.index++;
            if(root.index>=root.cases.length){report.setText(JSON.stringify(root.checks,null,2));Qt.quit();}
            else root.stage=0;
            break;
        }
    }}
    Component.onCompleted:{
        if(Quickshell.env('XDG_RUNTIME_DIR') !== '/tmp/gecko-ui-qa/runtime' || Quickshell.env('XDG_STATE_HOME') !== '/tmp/gecko-ui-qa/state') { console.error('Run only in the isolated UI test environment'); Qt.quit(); return; }
        Gecko.connected=true;Gecko.models=['sonnet'];Gecko.defaultModel='sonnet';
        Gecko.permissionModes=[{id:'default',label:'Manual',description:'Ask first'},
            {id:'acceptEdits',label:'Accept edits',description:'Accept edits'},
            {id:'plan',label:'Plan',description:'Plan'},
            {id:'auto',label:'Auto',description:'Auto'},
            {id:'dontAsk',label:"Don't ask",description:'Deny prompts'},
            {id:'bypassPermissions',label:'Full access',description:'Full access'}];
    }
}
