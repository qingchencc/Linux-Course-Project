#!/biin/bash
#简单的提醒逻辑
echo "提醒：现在是服药时间，请服用：$1"
cat <<EOF > notify.sh
#!/bin/bash
#简单的提醒逻辑
echo "提醒：现在是服药时间，请服用：$1"

#这里之后会接入wall命令或邮件通知[cite:20]
